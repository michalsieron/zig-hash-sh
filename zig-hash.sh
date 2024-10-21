#!/usr/bin/env sh

# Usage: zig-hash <path to build.zig.zon>
BUILD_ZIG_ZON="${1:-build.zig.zon}"
ROOT_DIR="$(dirname "$BUILD_ZIG_ZON")"

# Get hash of a file, which is computed from:
# - its normalized filepath
# - followed by two null bytes (apparently temporary solution in Zig, only for normal files)
# - followed by actual file content
hashFile() {
    filepath="$1"
    normalized="$(realpath --relative-to="$ROOT_DIR" "$filepath")"

    printf "%s:" "$filepath"

    if [ -f "$filepath" ] && [ -r "$filepath" ]; then
        (printf "%s\0\0" "$normalized"; cat "$filepath") | sha256sum | cut -d' ' -f1
    elif [ -h "$filepath" ]; then
        (printf "%s" "$normalized"; readlink -n "$filepath") | sha256sum | cut -d' ' -f1
    else
        printf "\r%s: is not a file, not a symlink, doesn't exist or isn't readable!\n" "$filepath" >&2
        exit 1
    fi
}

# Convert all incoming pairs or <filepath>:<hash> to a string
# of hash bytes, concatenate and hash again
combineHashes() {
    cut -d ':'  -f2 | xxd -r -p | sha256sum | cut -d' ' -f1
}

# List all files and symlinks that are part of the package:
# 1. Remove all comments
# 2. Remove all whitespace with `tr` to concatenate all lines
# 3. Extract content from `.paths=.{<content>}`
# 4. Replace all `","` with new lines
# 5. Remove initial quote (`"`) and trailing quote (`"`) with optional comma (`,`)
# 6. Prepend each line with $ROOT_DIR
# 7. Replace new lines with null bytes
# 8. Find all files and symlinks using content from earlier as starting points
# 9. Sort by filename
packageContent() {
    # shellcheck disable=SC2002
    # shellcheck disable=SC2185
    cat "${1}" \
        | sed 's|//.*||' \
        | tr -d '[:space:]' \
        | sed -E 's/.*\.paths=\.\{([^}]*)\}.*/\1/' \
        | sed 's/","/\n/g' \
        | sed -E -e 's/^"//; s/",?$/\n/' \
        | sed "s|^|$ROOT_DIR/|g" \
        | tr '\n' '\0' \
        | find -files0-from - -type f -or -type l 2>/dev/null \
        | LC_ALL=C sort
}

# 12 stands for sha256 and 20 is hash length in hex (32 in decimal)
printf "1220"

packageContent "$BUILD_ZIG_ZON" \
    | while read -r filepath; do
    hashFile "$filepath"
done | combineHashes
