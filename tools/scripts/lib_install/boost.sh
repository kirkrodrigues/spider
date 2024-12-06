#!/usr/bin/env bash

# Exit on error
set -e

# Treat unset variables as errors
set -u

cUsage="Usage: ${BASH_SOURCE[0]} <version> <libraries> [ <.deb output directory>]"
if [ "$#" -lt 2 ]; then
    echo "$cUsage"
    exit
fi
version=$1
libs_concatenated="$2"

package_name=libboost-dev-all
temp_dir="/tmp/${package_name}-installation"
deb_output_dir=${temp_dir}
if [[ "$#" -gt 2 ]] ; then
    deb_output_dir="$(readlink -f "$3")"
    if [ ! -d "$deb_output_dir" ] ; then
        echo "$deb_output_dir does not exist or is not a directory"
        exit
    fi
fi

# Check if already installed
set +e
pkg-config --exact-version="$version" "$package_name"
pkg_found=$?
static_lib_found=0
if [ $pkg_found -eq 0 ] ; then
    IFS="," read -r -a libs <<< "$libs_concatenated"
    for lib in "${libs[@]}"; do
        lib_filename="libboost_${lib}.a"
        find /usr/lib/ /usr/local/lib/ -name "$lib_filename" | grep -q "."
        static_lib_found=$?
        if [ $static_lib_found -ne 0 ]; then
            echo "$lib_filename not found."
            break
        fi
    done
fi
installed=$((pkg_found | static_lib_found))
set -e
if [ $installed -eq 0 ] ; then
    echo "Found ${package_name}=${version}."

    # Nothing to do
    exit
fi
echo "Checking for elevated privileges..."
privileged_command_prefix=""
if [ ${EUID:-$(id -u)} -ne 0 ] ; then
    sudo echo "Script can elevate privileges."
    privileged_command_prefix="sudo"
fi

# Download
mkdir -p $temp_dir
cd $temp_dir

version_with_underscores=${version//./_}
extracted_dir="${temp_dir}/boost_${version_with_underscores}"
if [ ! -e "$extracted_dir" ] ; then
    tar_filename=boost_${version_with_underscores}.tar.gz
    if [ ! -e "$tar_filename" ] ; then
        url="https://boostorg.jfrog.io/artifactory/main/release/${version}/source/${tar_filename}"
        curl --fail --silent --show-error \
                --location "$url" \
                --output "${tar_filename}"
    fi

    tar xf "$tar_filename"
fi

deb_pkg_name="${package_name}-${version}"
install_dir="${temp_dir}/${deb_pkg_name}"
install_usr_dir="${install_dir}/usr"
mkdir -p "$install_usr_dir"

# Build
cd "$extracted_dir"
./bootstrap.sh --with-libraries="$libs_concatenated --prefix=$install_usr_dir"
./b2 -j"$(nproc)"

# Install
./b2 install --prefix="$install_usr_dir"

metadata_dir="${install_dir}/DEBIAN"
mkdir -p "$metadata_dir"

cat <<EOF > "${metadata_dir}/control"
Package: $package_name
Architecture: $(dpkg --print-architecture)
Version: $version
Maintainer: YScope Inc. <dev@yscope.com>
Description: Boost C++ Libraries development file
Section: libdevel
Priority: optional
EOF

dpkg-deb --root-owner-group --build "$install_dir"
cp "${temp_dir}/${deb_pkg_name}.deb" "$deb_output_dir"

install_cmd=(
    "$privileged_command_prefix"
    dpkg
    -i "${deb_output_dir}/${deb_pkg_name}.deb"
)
DEBIAN_FRONTEND=noninteractive "${install_cmd[@]}"

# Clean up
rm -rf $temp_dir
