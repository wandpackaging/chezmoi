#!/bin/bash

set -euo pipefail

set -x

sudo apt-get update
sudo apt-get -y install binutils curl jq

git_tag="$(cd chezmoi && git describe --tags)"

github_api_url="https://api.github.com/repos/twpayne/chezmoi/releases/tags/${git_tag}"

package_path="${GITHUB_WORKSPACE}/packages/any-distro_any-version/"
mkdir -p "${package_path}"

mapfile -t deb_files < <(curl -1sLf "${github_api_url}" 2>/dev/null \
    | jq -r '.assets[] | select(.name | endswith(".deb")) | [.name, .browser_download_url] | @sh')

for deb_file in "${deb_files[@]}"; do
    pkg_filename=$(echo "${deb_file}" | awk '{print $1}' | xargs)
    pkg_url=$(echo "${deb_file}" | awk '{print $2}' | xargs)

    curl -1sLf "${pkg_url}" -o "${GITHUB_WORKSPACE}/${pkg_filename}"

    pkg_arch=$(dpkg -I "${GITHUB_WORKSPACE}/${pkg_filename}" | grep Architecture | awk '{print $2}')

    mv "${GITHUB_WORKSPACE}/${pkg_filename}" "${package_path}/${pkg_filename}"

    if [ "${pkg_arch}" == "arm" ]; then
        # Convert armel package to armhf
        mkdir -p "${GITHUB_WORKSPACE}/chezmoi_armhf/DEBIAN"
        ar p "${package_path}/${pkg_filename}" control.tar.gz | \
            tar -xz -C "${GITHUB_WORKSPACE}/chezmoi_armhf/DEBIAN"
        sed -i 's/Architecture: arm$/Architecture: armhf/' \
            "${GITHUB_WORKSPACE}/chezmoi_armhf/DEBIAN/control"
        (
          cd "${GITHUB_WORKSPACE}/chezmoi_armhf/DEBIAN/"; \
          tar -czf "${GITHUB_WORKSPACE}/chezmoi_armhf/control.tar.gz" -- *
        )
        armhf_filename=${pkg_filename//armel/armhf}
        cp "${package_path}/${pkg_filename}" "${GITHUB_WORKSPACE}/${armhf_filename}"
        ar r "${GITHUB_WORKSPACE}/${armhf_filename}" \
            "${GITHUB_WORKSPACE}/chezmoi_armhf/control.tar.gz"

        mv "${GITHUB_WORKSPACE}/${armhf_filename}" "${package_path}/${armhf_filename}"
    fi
done
