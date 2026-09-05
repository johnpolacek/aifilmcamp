#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper_root="$repo_root/Tools/ImageGenerationHelper"
required_node_version=v24.14.1
node_download_directory="$repo_root/.build/node-runtime-downloads"
mkdir -p "$node_download_directory"

node_platform_and_sha() {
  case "$1" in
    arm64)
      printf '%s %s\n' darwin-arm64 \
        25495ff85bd89e2d8a24d88566d7e2f827c6b0d3d872b2cebf75371f93fcb1fe
      ;;
    x86_64)
      printf '%s %s\n' darwin-x64 \
        2526230ad7d922be82d4fdb1e7ee1e84303e133e3b4b0ec4c2897ab31de0253d
      ;;
    *)
      echo "Unsupported image-helper build architecture: $1." >&2
      return 1
      ;;
  esac
}

prepare_node_runtime() {
  architecture=$1
  set -- $(node_platform_and_sha "$architecture")
  platform=$1
  sha256=$2
  archive_name="node-$required_node_version-$platform.tar.gz"
  archive="$node_download_directory/$archive_name"
  runtime="$repo_root/.build/node-runtime-$required_node_version-$platform"

  if [ ! -f "$archive" ]; then
    temporary_archive=$(mktemp "${TMPDIR%/}/filmcamp-node-archive.XXXXXX")
    trap 'rm -f "$temporary_archive"' EXIT HUP INT TERM
    curl --fail --location --retry 3 --silent --show-error \
      "https://nodejs.org/dist/$required_node_version/$archive_name" \
      --output "$temporary_archive"
    printf '%s  %s\n' "$sha256" "$temporary_archive" | shasum -a 256 -c - >/dev/null
    mv "$temporary_archive" "$archive"
    trap - EXIT HUP INT TERM
  fi
  printf '%s  %s\n' "$sha256" "$archive" | shasum -a 256 -c - >/dev/null

  if [ -e "$runtime" ] && [ ! -x "$runtime/bin/node" ]; then
    echo "Pinned Node runtime cache is incomplete: $runtime" >&2
    return 1
  fi
  if [ ! -x "$runtime/bin/node" ]; then
    temporary_runtime=$(mktemp -d "${TMPDIR%/}/filmcamp-node-runtime.XXXXXX")
    trap 'rm -rf "$temporary_runtime"' EXIT HUP INT TERM
    tar -xzf "$archive" -C "$temporary_runtime"
    mv "$temporary_runtime/node-$required_node_version-$platform" "$runtime"
    rmdir "$temporary_runtime"
    trap - EXIT HUP INT TERM
  fi
  printf '%s\n' "$runtime"
}

host_architecture=$(uname -m)
node_runtime=$(prepare_node_runtime "$host_architecture")

node_binary="$node_runtime/bin/node"
actual_node_version=$($node_binary --version)
if [ "$actual_node_version" != "$required_node_version" ]; then
  echo "Image helper requires Node $required_node_version; found $actual_node_version." >&2
  exit 1
fi

cd "$helper_root"
export PATH="$node_runtime/bin:$PATH"
if [ ! -d node_modules ]; then
  "$node_runtime/bin/npm" ci --ignore-scripts
fi
"$node_runtime/bin/npm" run build:js

output_directory=${FILMCAMP_IMAGE_HELPER_OUTPUT_DIR:-$helper_root/build}
case "$output_directory" in
  /*) ;;
  *) output_directory="$repo_root/$output_directory" ;;
esac
mkdir -p "$output_directory"
sea_config="$helper_root/build/sea-config.json"
sea_blob="$helper_root/build/sea-prep.blob"
helper_binary="$output_directory/filmcamp-image-helper"

sed \
  -e "s|__MAIN__|$helper_root/build/helper.cjs|" \
  -e "s|__OUTPUT__|$sea_blob|" \
  "$helper_root/sea-config.template.json" > "$sea_config"
"$node_binary" --experimental-sea-config "$sea_config"

build_architectures=${FILMCAMP_IMAGE_HELPER_ARCHITECTURES:-$host_architecture}
slice_directory=$(mktemp -d "${TMPDIR%/}/filmcamp-helper-slices.XXXXXX")
trap 'rm -rf "$slice_directory"' EXIT HUP INT TERM
slice_files=""
for architecture in $build_architectures; do
  runtime=$(prepare_node_runtime "$architecture")
  slice="$slice_directory/filmcamp-image-helper-$architecture"
  cp "$runtime/bin/node" "$slice"
  codesign --remove-signature "$slice" 2>/dev/null || true
  "$node_binary" "$helper_root/node_modules/postject/dist/cli.js" \
    "$slice" NODE_SEA_BLOB "$sea_blob" \
    --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 \
    --macho-segment-name NODE_SEA
  slice_files="$slice_files $slice"
done
set -- $slice_files
if [ "$#" -eq 1 ]; then
  mv "$1" "$helper_binary"
else
  lipo -create "$@" -output "$helper_binary"
fi
rm -rf "$slice_directory"
trap - EXIT HUP INT TERM
codesign --force --sign - "$helper_binary"
chmod 755 "$helper_binary"
"$helper_binary" --capabilities >/dev/null
