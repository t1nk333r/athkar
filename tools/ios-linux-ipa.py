"""Lays out, signs, archives and verifies Athkar.app for tools/ios-linux-ipa.sh.

The Xcode project that XcodeGen generated from ios/project.yml in the build snapshot
describes the app: the app target's Release settings, its Info.plist file and its
Resources phase. The published Xcode-built 1.0 (1) IPA is the layout this follows.
Python standard library only. See docs/agents/ios-linux.md.

    ios-linux-ipa.py name    --repo DIR
    ios-linux-ipa.py package --repo DIR --products DIR --sdk-bundle DIR --xcode-version PLIST
                             --rcodesign BIN --stage DIR --out-dir DIR --epoch SECONDS
"""

import argparse
import contextlib
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
import zlib
from pathlib import Path

PROJECT = "ios/Athkar.xcodeproj/project.pbxproj"
APPLICATION = "com.apple.product-type.application"
# TARGETED_DEVICE_FAMILY values and the actool --target-device names Xcode passes for them.
DEVICE_FAMILIES = {1: "iphone", 2: "ipad"}
LC_CODE_SIGNATURE = 0x1D
LC_BUILD_VERSION = 0x32
LC_RPATH = 0x8000001C
LOAD_DYLIB_COMMANDS = {0xC, 0x80000018, 0x8000001F, 0x80000023}
CPU_TYPE_ARM64 = 0x0100000C
PLATFORM_IOS = 2
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
CSSLOT_CODEDIRECTORY = 0
CSSLOT_ENTITLEMENTS = 5
CSSLOT_SIGNATURESLOT = 0x10000
CS_ADHOC = 0x2
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def die(message: str) -> None:
    print(f"ios-linux-ipa: {message}", file=sys.stderr)
    sys.exit(1)


def say(message: str) -> None:
    print(message, flush=True)


# -- project ------------------------------------------------------------------

OPENSTEP_TOKEN = re.compile(
    r'(\s+|/\*.*?\*/|//[^\n]*)|"((?:[^"\\]|\\.)*)"|((?:[^\s{}()=;,"/]|/(?![/*]))+)|([{}()=;,])', re.S)


def openstep(text: str):
    """Parses the old-style property list that Xcode and XcodeGen write as project.pbxproj."""
    tokens, pos = [], 0
    while pos < len(text):
        match = OPENSTEP_TOKEN.match(text, pos)
        if not match:
            die(f"cannot parse {PROJECT} at offset {pos}")
        pos = match.end()
        if match.group(2) is not None:
            unescaped = re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)),
                               match.group(2))
            tokens.append(("string", unescaped))
        elif match.group(3) is not None:
            tokens.append(("string", match.group(3)))
        elif match.group(4) is not None:
            tokens.append(("punct", match.group(4)))
    index = 0

    def expect(punct):
        nonlocal index
        if tokens[index] != ("punct", punct):
            die(f"{PROJECT}: expected {punct!r}, found {tokens[index][1]!r}")
        index += 1

    def value():
        nonlocal index
        kind, token = tokens[index]
        index += 1
        if kind == "string":
            return token
        if token == "{":
            result = {}
            while tokens[index] != ("punct", "}"):
                key = value()
                expect("=")
                result[key] = value()
                expect(";")
            index += 1
            return result
        if token == "(":
            result = []
            while tokens[index] != ("punct", ")"):
                result.append(value())
                if tokens[index] == ("punct", ","):
                    index += 1
            index += 1
            return result
        die(f"{PROJECT}: unexpected {token!r}")

    root = value()
    if index != len(tokens):
        die(f"{PROJECT}: trailing content after the root dictionary")
    return root


VARIABLE = re.compile(r"\$[({]([A-Za-z0-9_]+)(:[^)}]*)?[)}]")


class Project:
    """The application target of the generated project, with its Release settings resolved."""

    def __init__(self, repo: Path):
        self.repo = repo
        self.ios = repo / "ios"
        root = openstep((repo / PROJECT).read_text(encoding="utf-8"))
        self.objects = root["objects"]
        project = self.objects[root["rootObject"]]
        apps = [self.objects[i] for i in project["targets"] if self.objects[i].get("productType") == APPLICATION]
        if len(apps) != 1:
            die(f"expected one application target in {PROJECT}, found {len(apps)}")
        self.target = apps[0]
        self.name = self.target["name"]
        # Xcode's defaults for an application target, then the project and target Release levels.
        self.settings = {"TARGET_NAME": self.name, "PRODUCT_NAME": "$(TARGET_NAME)",
                         "EXECUTABLE_NAME": "$(PRODUCT_NAME)", "PRODUCT_BUNDLE_PACKAGE_TYPE": "APPL",
                         "DEVELOPMENT_LANGUAGE": project.get("developmentRegion", "en")}
        self.settings.update(self.release_settings(project))
        self.settings.update(self.release_settings(self.target))
        self.parents = {}
        for identifier, item in self.objects.items():
            if item.get("isa") in ("PBXGroup", "PBXVariantGroup"):
                for child in item.get("children", []):
                    self.parents[child] = identifier
        self.main_group = project["mainGroup"]

    def release_settings(self, owner: dict) -> dict:
        configurations = [self.objects[i] for i in self.objects[owner["buildConfigurationList"]]["buildConfigurations"]]
        release = [c for c in configurations if c.get("name") == "Release"]
        if len(release) != 1:
            die(f"{owner.get('name', 'project')} has {len(release)} Release configurations")
        return release[0]["buildSettings"]

    def setting(self, key: str, depth: int = 0) -> str:
        if key not in self.settings:
            die(f"the {self.name} Release configuration has no {key}")
        return self.expand(self.settings[key], depth)

    def expand(self, value: str, depth: int = 0) -> str:
        if depth > 16:
            die(f"build setting expansion does not terminate: {value}")

        def replace(match):
            if match.group(2):
                die(f"build setting operator {match.group(0)} is not supported")
            return self.setting(match.group(1), depth + 1)

        return VARIABLE.sub(replace, value)

    def expand_plist(self, value):
        if isinstance(value, str):
            return self.expand(value)
        if isinstance(value, list):
            return [self.expand_plist(v) for v in value]
        if isinstance(value, dict):
            return {k: self.expand_plist(v) for k, v in value.items()}
        return value

    def path(self, identifier: str) -> Path:
        """The repository file a reference names, resolved through its groups as Xcode does."""
        parts = []
        while identifier != self.main_group:
            item = self.objects[identifier]
            tree = item.get("sourceTree", "<group>")
            if tree == "SOURCE_ROOT":
                parts.append(item.get("path", ""))
                break
            if tree != "<group>":
                die(f"{item.get('name') or item.get('path')}: sourceTree {tree} is not supported")
            if "path" in item:
                parts.append(item["path"])
            if identifier not in self.parents:
                die(f"{item.get('name') or item.get('path')} is outside the main group")
            identifier = self.parents[identifier]
        path = Path(os.path.normpath(self.ios.joinpath(*reversed(parts))))
        if not path.is_relative_to(self.repo):
            die(f"{path} is outside the repository")
        return path

    def resources(self) -> list[tuple[dict, Path]]:
        phases = [self.objects[i] for i in self.target["buildPhases"]]
        unsupported = [p["isa"] for p in phases
                       if p["isa"] in ("PBXShellScriptBuildPhase", "PBXCopyFilesBuildPhase", "PBXHeadersBuildPhase")]
        if unsupported:
            die(f"{self.name} has build phases this packager does not perform: {unsupported}")
        phase = [p for p in phases if p["isa"] == "PBXResourcesBuildPhase"]
        if len(phase) != 1:
            die(f"{self.name} has {len(phase)} resource phases")
        result = []
        for build_file in phase[0]["files"]:
            identifier = self.objects[build_file]["fileRef"]
            reference = self.objects[identifier]
            if reference["isa"] != "PBXFileReference":
                die(f"resource {reference.get('name')}: {reference['isa']} is not supported")
            result.append((reference, self.path(identifier)))
        return result

    def info_plist(self) -> dict:
        with (self.ios / self.setting("INFOPLIST_FILE")).open("rb") as handle:
            return self.expand_plist(plistlib.load(handle))

    def families(self) -> list[int]:
        families = [int(f) for f in self.setting("TARGETED_DEVICE_FAMILY").split(",")]
        if not families or any(f not in DEVICE_FAMILIES for f in families):
            die(f"TARGETED_DEVICE_FAMILY {families} is not iPhone or iPad")
        return families


def ipa_name(project: Project, info: dict) -> str:
    return f"{project.setting('PRODUCT_NAME')}-{info['CFBundleShortVersionString']}+{info['CFBundleVersion']}-linux.ipa"


def name(args: argparse.Namespace) -> None:
    project = Project(Path(args.repo))
    print(ipa_name(project, project.info_plist()))


# -- PNG ----------------------------------------------------------------------


def png_decode(data: bytes) -> tuple[int, int, bytearray]:
    """Straight 8-bit RGBA pixels of a non-interlaced 8-bit grey, RGB or RGBA PNG."""
    if data[:8] != PNG_SIGNATURE:
        die("not a PNG")
    pos, header, idat = 8, None, []
    while pos < len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    if header is None:
        die("PNG without IHDR")
    width, height, depth, color, _, _, interlace = header
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color)
    if depth != 8 or channels is None or interlace != 0:
        die(f"PNG form depth={depth} color={color} interlace={interlace} is not supported")
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    pixels = bytearray(height * stride)
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 0xFF
        elif kind == 2:
            line = bytearray((a + b) & 0xFF for a, b in zip(line, previous))
        elif kind == 3:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + previous[x]) >> 1)) & 0xFF
        elif kind == 4:
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                b = previous[x]
                c = previous[x - channels] if x >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        elif kind != 0:
            die(f"PNG filter {kind}")
        pixels[y * stride:(y + 1) * stride] = line
        previous = line
    rgba = bytearray(width * height * 4)
    if channels >= 3:
        for channel in range(3):
            rgba[channel::4] = pixels[channel::channels]
    else:
        for channel in range(3):
            rgba[channel::4] = pixels[0::channels]
    rgba[3::4] = pixels[channels - 1::channels] if channels in (2, 4) else b"\xff" * (width * height)
    return width, height, rgba


def png_encode(width: int, height: int, rgba: bytearray) -> bytes:
    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    stride = width * 4
    raw = b"".join(b"\0" + bytes(rgba[y * stride:(y + 1) * stride]) for y in range(height))
    return (PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def downsample(width: int, rgba: bytearray, side: int) -> bytearray:
    """Area average of a square image with alpha-weighted colour, the method the Linux actool
    intends for its loose icons."""
    out = bytearray(side * side * 4)
    for y in range(side):
        y0, y1 = y * width // side, max(y * width // side + 1, (y + 1) * width // side)
        for x in range(side):
            x0, x1 = x * width // side, max(x * width // side + 1, (x + 1) * width // side)
            r = g = b = a = 0
            for sy in range(y0, y1):
                row = sy * width * 4
                for sx in range(x0, x1):
                    i = row + sx * 4
                    alpha = rgba[i + 3]
                    r += rgba[i] * alpha
                    g += rgba[i + 1] * alpha
                    b += rgba[i + 2] * alpha
                    a += alpha
            count = (y1 - y0) * (x1 - x0)
            o = (y * side + x) * 4
            if a:
                out[o:o + 3] = bytes(min(255, (2 * c + a) // (2 * a)) for c in (r, g, b))
            out[o + 3] = (2 * a + count) // (2 * count)
    return out


def uniform(rgba: bytearray) -> bool:
    return rgba == rgba[:4] * (len(rgba) // 4)


# -- Mach-O -------------------------------------------------------------------


def load_commands(data: bytes):
    if data[:4] != b"\xcf\xfa\xed\xfe" or len(data) < 32:
        die("the executable is not a thin 64-bit little-endian Mach-O")
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    offset, end = 32, 32 + sizeofcmds
    for _ in range(ncmds):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > end:
            die("malformed Mach-O load commands")
        yield command, offset, size
        offset += size


def command_string(data: bytes, offset: int, size: int) -> str:
    start = struct.unpack_from("<I", data, offset + 8)[0]
    return data[offset + start:offset + size].split(b"\0")[0].decode()


def host_rpath(rpath: str) -> bool:
    """Absolute rpaths other than the OS Swift runtime name build-host directories."""
    return rpath.startswith("/") and rpath != "/usr/lib/swift"


def prepare_executable(path: Path, sdk_version: str) -> list[str]:
    """Drops build-host rpaths as install_name_tool -delete_rpath does and records the SDK in
    LC_BUILD_VERSION, where the Linux link writes the deployment target instead."""
    data = bytearray(path.read_bytes())
    if struct.unpack_from("<I", data, 4)[0] != CPU_TYPE_ARM64:
        die(f"{path.name} is not arm64")
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    sdk = sum(int(p) << s for p, s in zip((sdk_version.split(".") + ["0", "0"])[:3], (16, 8, 0)))
    kept, count, dropped, builds = bytearray(), 0, [], 0
    for command, offset, size in list(load_commands(data)):
        blob = bytearray(data[offset:offset + size])
        if command == LC_RPATH and host_rpath(command_string(data, offset, size)):
            dropped.append(command_string(data, offset, size))
            continue
        if command == LC_BUILD_VERSION:
            if struct.unpack_from("<I", blob, 8)[0] != PLATFORM_IOS:
                die(f"{path.name} is not built for iOS")
            struct.pack_into("<I", blob, 16, sdk)
            builds += 1
        kept += blob
        count += 1
    if builds != 1:
        die(f"{path.name} has {builds} LC_BUILD_VERSION commands")
    data[32:32 + sizeofcmds] = kept + bytes(sizeofcmds - len(kept))
    struct.pack_into("<II", data, 16, count, len(kept))
    path.write_bytes(data)
    return dropped


def version_text(raw: int) -> str:
    return f"{raw >> 16}.{(raw >> 8) & 0xFF}"


def macho_facts(data: bytes) -> dict:
    facts = {"cpu": struct.unpack_from("<I", data, 4)[0], "dylibs": [], "rpaths": [], "build": None,
             "signature": None}
    for command, offset, size in load_commands(data):
        if command == LC_BUILD_VERSION:
            platform, minos, sdk = struct.unpack_from("<III", data, offset + 8)
            facts["build"] = (platform, version_text(minos), version_text(sdk))
        elif command == LC_RPATH:
            facts["rpaths"].append(command_string(data, offset, size))
        elif command in LOAD_DYLIB_COMMANDS:
            facts["dylibs"].append(command_string(data, offset, size))
        elif command == LC_CODE_SIGNATURE:
            facts["signature"] = signature_facts(data, *struct.unpack_from("<II", data, offset + 8))
    return facts


def signature_facts(data: bytes, offset: int, size: int) -> dict:
    region = data[offset:offset + size]
    magic, length, count = struct.unpack_from(">III", region, 0)
    if magic != CSMAGIC_EMBEDDED_SIGNATURE or length > size:
        die("the code signature is not an embedded signature super blob")
    facts = {"offset": offset, "slots": {}, "blobs": {}, "identifier": None, "flags": None}
    for index in range(count):
        slot, blob = struct.unpack_from(">II", region, 12 + index * 8)
        blob_magic, blob_length = struct.unpack_from(">II", region, blob)
        facts["slots"][slot] = blob_length
        facts["blobs"][slot] = region[blob:blob + blob_length]
        if slot == CSSLOT_CODEDIRECTORY and blob_magic == CSMAGIC_CODEDIRECTORY:
            flags, = struct.unpack_from(">I", region, blob + 12)
            ident, = struct.unpack_from(">I", region, blob + 20)
            facts["flags"] = flags
            facts["identifier"] = region[blob + ident:blob + blob_length].split(b"\0")[0].decode()
    return facts


CODE_DIRECTORY_HASHES = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}
# Special slots by number: Info.plist, requirements, CodeResources, entitlements, DER entitlements.
SPECIAL_SLOTS = {1: "Info.plist", 2: "requirements", 3: "CodeResources", 5: "entitlements", 7: "DER entitlements"}


def code_directory_failures(data: bytes, signature: dict, sources: dict) -> tuple[list[str], str]:
    """Recomputes every code page hash and special slot of each code directory. An ad hoc
    signature has no CMS signature to check, so these hashes are the whole signature.
    rcodesign 0.29.0's `verify` cannot parse the empty CMS blob that Apple's codesign also
    writes for ad hoc signatures, so it fails on the published Xcode build as well."""
    sources = {**sources, 2: signature["blobs"].get(2), 5: signature["blobs"].get(5), 7: signature["blobs"].get(7)}
    failures, summary = [], []
    directories = [s for s in signature["blobs"] if s == CSSLOT_CODEDIRECTORY or 0x1000 <= s < 0x1005]
    if not directories:
        return ["no code directory"], ""
    for slot in directories:
        cd = signature["blobs"][slot]
        (magic, _, version, _, hash_offset, _, special_count, code_count, code_limit,
         hash_size, hash_type, _, page_log) = struct.unpack_from(">IIIIIIIIIBBBB", cd, 0)
        if version >= 0x20300 and code_limit == 0:
            code_limit, = struct.unpack_from(">Q", cd, 56)
        algorithm = CODE_DIRECTORY_HASHES.get(hash_type)
        if magic != CSMAGIC_CODEDIRECTORY or algorithm is None:
            failures.append(f"code directory slot {slot:#x} has magic {magic:#x} and hash type {hash_type}")
            continue
        page = 1 << page_log if page_log else code_limit
        if code_limit != signature["offset"] or code_count != -(-code_limit // page):
            failures.append(f"code directory covers {code_limit} bytes in {code_count} pages, "
                            f"not the {signature['offset']} bytes before the signature")
        bad = [i for i in range(code_count)
               if hashlib.new(algorithm, data[i * page:min((i + 1) * page, code_limit)]).digest()[:hash_size]
               != cd[hash_offset + i * hash_size:hash_offset + (i + 1) * hash_size]]
        if bad:
            failures.append(f"{algorithm} code pages {bad[:8]} of {code_count} do not match")
        for number in range(1, special_count + 1):
            stored = cd[hash_offset - number * hash_size:hash_offset - (number - 1) * hash_size]
            source = sources.get(number)
            expected = bytes(hash_size) if source is None else hashlib.new(algorithm, source).digest()[:hash_size]
            if stored != expected:
                failures.append(f"{algorithm} special slot {number} ({SPECIAL_SLOTS.get(number, 'unused')}) does not match")
        summary.append(f"{algorithm} {code_count} pages of {page} bytes, {special_count} special slots")
    return failures, "; ".join(summary)


# -- layout -------------------------------------------------------------------


def sdk_keys(sdk_bundle: Path, xcode_version: Path) -> tuple[str, dict]:
    """The build-environment keys Xcode writes, from the SDK and the Xcode it was taken from."""
    sdk = sdk_bundle / "Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    settings = json.loads((sdk / "SDKSettings.json").read_text())
    with (sdk / "System/Library/CoreServices/SystemVersion.plist").open("rb") as handle:
        sdk_build = plistlib.load(handle)["ProductBuildVersion"]
    with xcode_version.open("rb") as handle:
        xcode = plistlib.load(handle)
    major, minor, patch = (xcode["CFBundleShortVersionString"].split(".") + ["0", "0"])[:3]
    return settings["Version"], {
        "DTCompiler": "com.apple.compilers.llvm.clang.1_0",
        "DTPlatformBuild": sdk_build,
        "DTPlatformName": "iphoneos",
        "DTPlatformVersion": settings["Version"],
        "DTSDKBuild": sdk_build,
        "DTSDKName": settings["CanonicalName"],
        "DTXcode": f"{int(major):02d}{minor}{patch}",
        "DTXcodeBuild": xcode["ProductBuildVersion"],
    }


def add_keys(info: dict, keys: dict, label: str) -> None:
    for key, value in keys.items():
        if key in info and info[key] != value:
            die(f"{label} declares {key}={info[key]!r}; Xcode would write {value!r}")
        info[key] = value


def write_plist(path: Path, data: dict) -> None:
    with path.open("wb") as handle:
        plistlib.dump(data, handle, fmt=plistlib.FMT_BINARY, sort_keys=True)


def compile_catalogs(project: Project, catalogs: list[Path], app: Path, actool: Path) -> dict:
    devices = [DEVICE_FAMILIES[f] for f in project.families()]
    icon = project.setting("ASSETCATALOG_COMPILER_APPICON_NAME")
    with tempfile.TemporaryDirectory() as tmp:
        partial = Path(tmp) / "partial.plist"
        command = [str(actool), *map(str, catalogs), "--compile", str(app), "--platform", "iphoneos",
                   "--minimum-deployment-target", project.setting("IPHONEOS_DEPLOYMENT_TARGET"),
                   "--app-icon", icon, "--output-partial-info-plist", str(partial),
                   "--output-format", "human-readable-text"]
        for device in devices:
            command += ["--target-device", device]
        say("actool: " + " ".join(command))
        result = subprocess.run(command, capture_output=True, text=True)
        noise = re.compile(r"libxml2\.so\.2: no version information available")
        stderr = "\n".join(line for line in result.stderr.splitlines() if not noise.search(line))
        if stderr:
            print(stderr, file=sys.stderr)
        print(result.stdout, end="")
        sections = set(re.findall(r"/\* (com\.apple\.actool\.[\w.-]+) \*/", result.stdout))
        if result.returncode != 0 or sections - {"com.apple.actool.compilation-results"}:
            die(f"actool failed ({result.returncode}) or reported {sorted(sections)}")
        with partial.open("rb") as handle:
            keys = plistlib.load(handle)
    if not (app / "Assets.car").is_file():
        die("actool wrote no Assets.car")
    repair_loose_icons(catalogs, icon, keys, app)
    return keys


def repair_loose_icons(catalogs: list[Path], icon: str, keys: dict, app: Path) -> None:
    """The Linux actool's loose-icon downsampler (darwin-tools d993142,
    SingleSizeIcon.downsampleRGBA) multiplies the alpha-weighted colour by 255 again, so every
    opaque pixel saturates and each loose PNG is solid white. SpringBoard can read these PNGs
    when its Assets.car lookup misses. A uniform output from a varied source is that defect;
    it is replaced by the same area average, computed correctly from the same source image."""
    names = {name for k in ("CFBundleIcons", "CFBundleIcons~ipad")
             for name in keys.get(k, {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconFiles", [])}
    sets = [c / f"{icon}.appiconset" for c in catalogs if (c / f"{icon}.appiconset").is_dir()]
    if len(sets) != 1:
        die(f"expected one {icon}.appiconset, found {len(sets)}")
    contents = json.loads((sets[0] / "Contents.json").read_text())
    base = [i for i in contents["images"] if "appearances" not in i and i.get("filename")]
    if len(base) != 1 or base[0].get("size") != "1024x1024" or base[0].get("idiom") != "universal":
        die(f"{icon} is not a single-size 1024 universal icon")
    source = None
    for path in sorted(app.glob(f"{icon}*.png")):
        match = re.fullmatch(rf"{re.escape(icon)}(\d+)x\1@(\d)x(~ipad)?\.png", path.name)
        if not match or path.name.split("@")[0] not in names:
            die(f"actool wrote an unexpected icon {path.name}")
        side = int(match.group(1)) * int(match.group(2))
        width, height, pixels = png_decode(path.read_bytes())
        if (width, height) != (side, side):
            die(f"{path.name} is {width}x{height}, not {side}x{side}")
        if not uniform(pixels):
            continue
        if source is None:
            source = png_decode((sets[0] / base[0]["filename"]).read_bytes())
            if source[0] != source[1] or uniform(source[2]):
                die(f"cannot repair {path.name}: the source icon is not a varied square image")
        path.write_bytes(png_encode(side, side, downsample(source[0], source[2], side)))
        say(f"replaced actool's uniform {path.name} with a {side}x{side} area average of "
            f"{base[0]['filename']} (known Linux actool downsampler defect)")
    for name in names:
        if not any(app.glob(f"{name}@*.png")):
            die(f"actool wrote no loose PNG for {name}")


def layout(args: argparse.Namespace, project: Project) -> tuple[Path, dict]:
    stage, products = Path(args.stage), Path(args.products)
    app = stage / "Payload" / f"{project.setting('PRODUCT_NAME')}.app"
    app.mkdir(parents=True)
    executable = project.setting("EXECUTABLE_NAME")
    shutil.copyfile(products / executable, app / executable)
    os.chmod(app / executable, 0o755)
    sdk_version, dt_keys = sdk_keys(Path(args.sdk_bundle), Path(args.xcode_version))
    dropped = prepare_executable(app / executable, sdk_version)
    say(f"executable: dropped build-host rpaths {dropped}; LC_BUILD_VERSION sdk {sdk_version}")

    # Xcode copies each Resources-phase file to the bundle root and compiles asset catalogs.
    catalogs, copied = [], {}
    for reference, path in project.resources():
        kind = reference.get("lastKnownFileType", "")
        if kind == "folder.assetcatalog" or path.suffix == ".xcassets":
            catalogs.append(path)
            continue
        if not path.is_file() or path.suffix in (".strings", ".stringsdict", ".xcstrings", ".xib",
                                                 ".storyboard", ".plist", ".xcdatamodeld", ".intentdefinition"):
            die(f"resource {path} needs a build step this packager does not perform")
        if path.name in copied:
            die(f"two resources are named {path.name}")
        shutil.copyfile(path, app / path.name)
        copied[path.name] = path
        say(f"resource: {path.relative_to(project.repo)} -> {path.name}")
    families = project.families()
    icon_keys = compile_catalogs(project, catalogs, app, Path(args.sdk_bundle)
                                 / "Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/actool") if catalogs else {}

    # SwiftPM resource bundles of linked packages, as Xcode embeds them. The adapter's own
    # bundle for the app target holds the staged copies of the resources copied above.
    own = [b for b in products.glob(f"*_{project.name}.bundle")]
    if len(own) != 1:
        die(f"expected the adapter's own *_{project.name}.bundle, found {own}")
    for bundle in sorted(products.glob("*.bundle")):
        if bundle in own:
            continue
        destination = app / bundle.name
        shutil.copytree(bundle, destination, symlinks=True)
        with (destination / "Info.plist").open("rb") as handle:
            bundle_info = plistlib.load(handle)
        # SwiftBuild records a placeholder Xcode (10989, 99T999) and no platform build.
        bundle_info.update(dt_keys)
        bundle_info.setdefault("UIDeviceFamily", families)
        write_plist(destination / "Info.plist", bundle_info)
        say(f"package resources: {bundle.name}")

    # The keys Xcode adds while processing Info.plist for an arm64 iphoneos build.
    info = project.info_plist()
    add_keys(info, {
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "MinimumOSVersion": project.setting("IPHONEOS_DEPLOYMENT_TARGET"),
        "UIDeviceFamily": families,
        "UIRequiredDeviceCapabilities": ["arm64"],
        **dt_keys,
        **icon_keys,
    }, "ios/project.yml")
    if info.get("CFBundleExecutable") != executable:
        die(f"CFBundleExecutable {info.get('CFBundleExecutable')} is not {executable}")
    write_plist(app / "Info.plist", info)
    (app / "PkgInfo").write_bytes(info["CFBundlePackageType"].encode() + info.get("CFBundleSignature", "????").encode())
    return app, info


def sign(app: Path, rcodesign: str) -> None:
    """Ad hoc, with no identity and no entitlements, like the published Xcode build. The empty
    configuration keeps rcodesign from loading any default signing settings. Shallow signing
    seals resource bundles, which have no executable, in the app's CodeResources as Xcode
    does, instead of giving each its own. `verify` checks the result in the archive."""
    command = [rcodesign, "sign", "--config-file", "/dev/null", "--shallow", str(app)]
    say(" ".join(command))
    result = subprocess.run(command, capture_output=True, text=True)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        die(f"rcodesign sign failed ({result.returncode})")


# -- archive ------------------------------------------------------------------


def write_archive(stage: Path, handle, epoch: int) -> None:
    """Zips stage/Payload with Unix modes and a fixed time, without extra fields such as
    extended attributes, refusing anything that is not a file or directory."""
    when = time.gmtime(max(epoch, 315532800))[:6]
    with zipfile.ZipFile(handle, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for root, dirs, files in os.walk(stage / "Payload"):
            dirs.sort()
            relative = Path(root).relative_to(stage)
            entry = zipfile.ZipInfo(f"{relative}/", when)
            entry.create_system = 3
            entry.external_attr = ((stat.S_IFDIR | 0o755) << 16) | 0x10
            archive.writestr(entry, b"")
            for name in sorted(dirs + files):
                mode = os.lstat(Path(root) / name).st_mode
                if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
                    die(f"{Path(root) / name} is neither a file nor a directory")
            for name in sorted(files):
                path = Path(root) / name
                entry = zipfile.ZipInfo(str(relative / name), when)
                entry.create_system = 3
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = (stat.S_IFREG | (0o755 if os.access(path, os.X_OK) else 0o644)) << 16
                archive.writestr(entry, path.read_bytes())


def unsealed_files(files: dict, executable: str) -> list[str]:
    """Archived files whose CodeResources files2 hash is missing or differs. The executable,
    Info.plist and PkgInfo are sealed by the code directory or omitted, as Xcode's rules do."""
    sealed = plistlib.loads(files["_CodeSignature/CodeResources"]).get("files2", {})
    problems = []
    for name, data in files.items():
        if name.startswith("_CodeSignature/") or name in (executable, "Info.plist", "PkgInfo"):
            continue
        record = sealed.get(name)
        if not isinstance(record, dict) or record.get("hash2") != hashlib.sha256(data).digest():
            problems.append(name)
    return problems


def verify(ipa: Path, project: Project, expected: dict) -> list[str]:
    """Independent checks of the archive as it will be published; returns the report lines."""
    failures, report = [], []

    def check(ok: bool, what: str) -> None:
        (report if ok else failures).append(("ok   " if ok else "FAIL ") + what)

    app_name = project.setting("PRODUCT_NAME")
    prefix = f"Payload/{app_name}.app/"
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.infolist()
        names = [e.filename for e in entries]
        check(len(names) == len(set(names)), "no duplicate archive entries")
        check(all(n.startswith("Payload/") and ".." not in n.split("/") for n in names), "everything is under Payload/")
        check(not any(Path(n.rstrip("/")).name.startswith("._") or "__MACOSX" in n or n.endswith(".DS_Store")
                      for n in names), "no AppleDouble or Finder metadata")
        check(all(not e.extra for e in entries), "no extra fields (extended attributes)")
        check(all(stat.S_IFMT(e.external_attr >> 16) in (stat.S_IFREG, stat.S_IFDIR) for e in entries),
              "only regular files and directories")
        files = {e.filename[len(prefix):]: archive.read(e) for e in entries
                 if e.filename.startswith(prefix) and not e.is_dir()}
    info = plistlib.loads(files["Info.plist"])
    check(info == expected, "Info.plist is the generated and stamped dictionary")
    executable = info["CFBundleExecutable"]
    facts = macho_facts(files[executable])
    check(facts["cpu"] == CPU_TYPE_ARM64, f"{executable} is arm64")
    platform, minos, sdk = facts["build"]
    check(platform == PLATFORM_IOS and minos == info["MinimumOSVersion"],
          f"LC_BUILD_VERSION platform {platform} (iOS) minos {minos}")
    check(sdk == info["DTPlatformVersion"], f"LC_BUILD_VERSION sdk {sdk}")
    check(not any(host_rpath(r) for r in facts["rpaths"]), f"no build-host rpath: {facts['rpaths']}")
    check(all(d.startswith(("/System/Library/", "/usr/lib/")) for d in facts["dylibs"]),
          f"only system libraries are loaded ({len(facts['dylibs'])})")
    check(not any(d.endswith("/SwiftUICore") for d in facts["dylibs"]), "SwiftUICore is not loaded directly")
    signature = facts["signature"] or {"slots": {}}
    check(signature.get("flags") is not None and signature["flags"] & CS_ADHOC, "ad hoc code directory")
    check(signature.get("identifier") == info["CFBundleIdentifier"],
          f"signing identifier {signature.get('identifier')}")
    check(signature["slots"].get(CSSLOT_SIGNATURESLOT, 8) <= 8, "no CMS signature (no identity)")
    check(CSSLOT_ENTITLEMENTS not in signature["slots"], "no entitlements")
    if facts["signature"]:
        broken, summary = code_directory_failures(
            files[executable], signature, {1: files["Info.plist"], 3: files.get("_CodeSignature/CodeResources")})
        check(not broken, f"code directory hashes match: {summary or broken}")
    unsealed = unsealed_files(files, executable)
    check(not unsealed, f"CodeResources seals every resource {unsealed}")
    nested = sorted(n for n in files if "/_CodeSignature/" in n)
    check(not nested, f"only the app carries a code signature {nested}")
    for reference, path in project.resources():
        if path.suffix == ".xcassets":
            continue
        check(files.get(path.name) == path.read_bytes(),
              f"{path.name} equals {path.relative_to(project.repo)} (sha256 {hashlib.sha256(path.read_bytes()).hexdigest()})")
    if "manifest.json" in files:
        for pack in json.loads(files["manifest.json"])["packs"].values():
            data = files.get(pack["file"])
            check(data is not None and hashlib.sha256(data).hexdigest() == pack["sha256"],
                  f"{pack['file']} matches manifest.json sha256 {pack['sha256']}")
    for font in info.get("UIAppFonts", []):
        check(font in files, f"UIAppFonts {font} is at the bundle root")
    check("Assets.car" in files and "PkgInfo" in files, "Assets.car and PkgInfo")
    icons = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    check(icons.get("CFBundleIconName") == project.setting("ASSETCATALOG_COMPILER_APPICON_NAME"), "primary icon name")
    for name in sorted(n for n in files if n.endswith(".png") and "/" not in n):
        width, height, pixels = png_decode(files[name])
        check(not uniform(pixels), f"{name} ({width}x{height}) is not a uniform placeholder")
    for bundle in sorted({n.split("/")[0] for n in files if n.endswith(".bundle/Info.plist")}):
        bundle_info = plistlib.loads(files[f"{bundle}/Info.plist"])
        check(bundle_info.get("CFBundlePackageType") == "BNDL" and bundle_info.get("DTXcode") == info["DTXcode"],
              f"{bundle} is a stamped resource bundle")
    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        die(f"{len(failures)} verification check(s) failed on {ipa.name}")
    return report


def publish(args: argparse.Namespace, project: Project, info: dict) -> None:
    out = Path(args.out_dir)
    final = out / ipa_name(project, info)
    digest_file = out / f"{final.name}.sha256"
    for path in (final, digest_file):
        if os.path.lexists(path):
            die(f"{path} exists; a version is built once")
    fd, temporary = tempfile.mkstemp(prefix=f".{final.name}.", suffix=".tmp", dir=out)
    try:
        with os.fdopen(fd, "wb") as handle:
            write_archive(Path(args.stage), handle, args.epoch)
            handle.flush()
            os.fsync(handle.fileno())
        report = verify(Path(temporary), project, info)
        for line in report:
            print(line)
        os.chmod(temporary, 0o644)
        digest = hashlib.sha256(Path(temporary).read_bytes()).hexdigest()
        # A hard link fails rather than replace an IPA another build published meanwhile.
        try:
            os.link(temporary, final, follow_symlinks=False)
        except FileExistsError:
            die(f"{final} appeared while this build ran; left it unchanged")
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)
    fd, temporary = tempfile.mkstemp(prefix=f".{digest_file.name}.", suffix=".tmp", dir=out)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(f"{digest}  {final.name}\n")
        os.chmod(temporary, 0o644)
        try:
            os.link(temporary, digest_file, follow_symlinks=False)
        except FileExistsError:
            die(f"{digest_file} appeared while this build ran; left it unchanged")
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)
    print(f"wrote {final} ({final.stat().st_size} bytes, sha256 {digest})")
    print(f"wrote {digest_file}")


def package(args: argparse.Namespace) -> None:
    project = Project(Path(args.repo))
    app, info = layout(args, project)
    sign(app, args.rcodesign)
    publish(args, project, info)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("name")
    p.add_argument("--repo", required=True)
    p = sub.add_parser("package")
    for option in ("--repo", "--products", "--sdk-bundle", "--xcode-version", "--rcodesign", "--stage", "--out-dir"):
        p.add_argument(option, required=True)
    p.add_argument("--epoch", type=int, required=True)
    args = parser.parse_args()
    {"name": name, "package": package}[args.command](args)


if __name__ == "__main__":
    main()
