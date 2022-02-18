#!/bin/bash

set -euo pipefail

github_api_url="https://api.github.com/repos/twpayne/chezmoi/releases/latest"
cloudsmith_config_url="https://dl.cloudsmith.io/public/wand/chezmoi/config.deb.txt?distro=$(lsb_release -is)&codename=$(lsb_release -sc)"

deb_repo_url=$(curl -1sLf "${cloudsmith_config_url}" | grep "deb " | awk '{print $2}')

mapfile -t deb_files < <(curl -1sLf "${github_api_url}" 2>/dev/null \
    | jq -r '.assets[] | select(.name | endswith(".deb")) | [.name, .browser_download_url] | @sh')

new_packages=0
for deb_file in "${deb_files[@]}"; do
    pkg_filename=$(echo "${deb_file}" | awk '{print $1}' | xargs)
    pkg_url=$(echo "${deb_file}" | awk '{print $2}' | xargs)

    curl -1sLf "${pkg_url}" -o "${GITHUB_WORKSPACE}/${pkg_filename}"

    pkg_arch=$(dpkg -I "${GITHUB_WORKSPACE}/${pkg_filename}" | grep Architecture | awk '{print $2}')

    deb_repo_packages_url="${deb_repo_url}/dists/$(lsb_release -sc)/main/binary-${pkg_arch}/Packages"

    package_path="${GITHUB_WORKSPACE}/packages/any-distro_any-version/"
    mkdir -p "${package_path}"

    if ! curl -1sLf "${deb_repo_packages_url}" 2>&1 | grep "${pkg_filename}" > /dev/null; then
        mv "${GITHUB_WORKSPACE}/${pkg_filename}" "${package_path}/${pkg_filename}"
        new_packages=$((new_packages+=1))

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

            if ! curl -1sLf "${deb_repo_packages_url}" 2>&1 | grep "${armhf_filename}" > /dev/null; then
                mv "${GITHUB_WORKSPACE}/${armhf_filename}" "${package_path}/${armhf_filename}"
                new_packages=$((new_packages+=1))
            fi
        fi
    fi
done

echo "NEW_PACKAGES=${new_packages}" >> "${GITHUB_ENV}"
