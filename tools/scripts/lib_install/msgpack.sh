#!/bin/bash

# Dependencies:
# - Boost
# NOTE: Dependencies should be installed outside the script to allow the script to be largely distro-agnostic

# Exit on any error
set -e

cUsage="Usage: ${BASH_SOURCE[0]} <version>[ <.deb output directory>]"
if [ "$#" -lt 1 ] ; then
    echo $cUsage
    exit
fi
version=$1

package_name=libmsgpack-cxx-dev
temp_dir=/tmp/${package_name}-installation
deb_output_dir=${temp_dir}
if [[ "$#" -gt 1 ]] ; then
  deb_output_dir="$(readlink -f "$2")"
  if [ ! -d ${deb_output_dir} ] ; then
    echo "${deb_output_dir} does not exist or is not a directory"
    exit
  fi
fi

# Check if already installed
set +e
dpkg -l ${package_name} | grep ${version}
installed=$?
set -e
if [ $installed -eq 0 ] ; then
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
extracted_dir=${temp_dir}/msgpack-cxx-${version}
if [ ! -e ${extracted_dir} ] ; then
  tar_filename=msgpack-cxx-${version}.tar.gz
  if [ ! -e ${tar_filename} ] ; then
    curl -fsSL https://github.com/msgpack/msgpack-c/releases/download/cpp-${version}/${tar_filename} -o ${tar_filename}
  fi

  tar -xf ${tar_filename}
fi

# Set up
cd ${extracted_dir}
mkdir -p cmake-build-release
cmake -S . -B cmake-build-release -DCMAKE_BUILD_TYPE=Release

###
# INSTALL
###
deb_pkg_name="${package_name}-${version}"
install_dir="${temp_dir}/${deb_pkg_name}"
mkdir -p "$install_dir"

cmake --install cmake-build-release --prefix "$install_dir/usr"

metadata_dir="${install_dir}/DEBIAN"
mkdir -p "$metadata_dir"

cat <<EOF > "${metadata_dir}/control"
Package: $package_name
Architecture: $(dpkg --print-architecture)
Version: $version
Maintainer: YScope Inc. <dev@yscope.com>
Description: binary-based efficient object serialization library (development files)
Section: libdevel
Priority: optional
EOF

cd "$deb_output_dir"
dpkg-deb --root-owner-group --build "$install_dir"
install_cmd=(
    "$privileged_command_prefix"
    dpkg
    -i "${deb_output_dir}/${deb_pkg_name}.deb"
)
DEBIAN_FRONTEND=noninteractive "${install_cmd[@]}"

# Clean up
rm -rf $temp_dir