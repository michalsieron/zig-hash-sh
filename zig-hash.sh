#!/usr/bin/env sh

# Copyright 2024 Michał Sieroń <michalwsieron@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”),
# to deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

ROOT_DIR="${1}"
if [ ! -d "${ROOT_DIR}" ] || [ ! -r "${ROOT_DIR}" ]; then
    echo "Usage: zig-hash <root dir path>" >&2
    exit 1
fi

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
# 1. If path has build.zig.zon:
#   1.1. Remove all comments
#   1.2. Remove all whitespace with `tr` to concatenate all lines
#   1.3. Extract content from `.paths=.{<content>}`
#   1.4. Replace all `","` with new lines
#   1.5. Remove initial quote (`"`) and trailing quote (`"`) with optional comma (`,`)
#   1.6. Prepend each line with $ROOT_DIR
#   1.7. Replace new lines with null bytes
# 2. Else match any file
# 3. Find all files and symlinks using content from earlier as starting points
# 4. Sort by filename
packageContent() {
    # shellcheck disable=SC2002
    # shellcheck disable=SC2185
    {
        if [ -f "${1}/build.zig.zon" ]; then
            cat "${1}/build.zig.zon" \
                | sed 's|//.*||' \
                | tr -d '[:space:]' \
                | sed -E 's/.*\.paths=\.\{([^}]*)\}.*/\1/' \
                | sed 's/","/\n/g' \
                | sed -E -e 's/^"//; s/",?$/\n/' \
                | sed "s|^|${ROOT_DIR}/|g" \
                | tr '\n' '\0'
        else
            printf '%s\0' "${ROOT_DIR}"
        fi
    } \
        | find -files0-from - -type f -or -type l 2>/dev/null \
        | LC_ALL=C sort
}

# 12 stands for sha256 and 20 is hash length in hex (32 in decimal)
printf "1220"

packageContent "${ROOT_DIR}" \
    | while read -r filepath; do
    hashFile "${filepath}"
done | combineHashes
