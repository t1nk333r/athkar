# data

## cities.tsv

The offline city list behind manual location in the iOS app: search by name (Arabic or English) and the city name on
the location card and in القبلة. Nothing typed into the search leaves the device.

- **Source:** [GeoNames](https://www.geonames.org/) dumps from https://download.geonames.org/export/dump/, downloaded
  2026-09-28:
  - `cities15000.zip`: sha256 `2b63225616ed25a77577883b073ba65531e545e682ca9e2eddfaa776d3bd3972`
  - `alternateNamesV2.zip`: sha256 `498798fcc3df8a4715db07b4c22dd503c8aae5c4fa804da637af0229eab4ad91`
- **Licence:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The app credits GeoNames under the city
  search.
- **Contents:** 34,146 places with at least 15,000 people. 8,895 have an Arabic name: GeoNames' `ar` names,
  or for a city in a country where Arabic is official, an untagged Arabic-script alternate. The rest are searchable by
  their Latin name only.
- **Rebuild:** unzip both dumps into one directory, then run:

  ```bash
  node tools/cities-build.mjs <that directory>
  ```

  The iOS app bundles the file as is (see `ios/project.yml`), and `AthkarCore`'s `CityIndex` parses it.
