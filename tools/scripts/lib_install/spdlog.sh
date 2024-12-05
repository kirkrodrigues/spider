#!/bin/bash

# Dependencies:
# - cmake
# - curl
# - g++
# NOTE: Dependencies should be installed outside the script to allow the script to be largely distro-agnostic

# Exit on any error
set -e

cUsage="Usage: ${BASH_SOURCE[0]} <version>[ <.deb output directory>]"
if [ "$#" -lt 1 ] ; then
    echo $cUsage
    exit
fi
version=$1

lib_name=spdlog
package_name=libspdlog-dev
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
pkg-config --exact-version="${version}" "${lib_name}"
pkg_found=$?
if [ $pkg_found -eq 0 ] ; then
  find /usr/lib/ /usr/local/lib/ -name "libspdlog.a" | grep -q "."
  static_lib_found=$?
fi
installed=$((pkg_found | static_lib_found))
set -e
if [ $installed -eq 0 ] ; then
  echo "Found ${lib_name}=${version}."
  # Nothing to do
  exit
fi

echo "Checking for elevated privileges..."
privileged_command_prefix=""
if [ ${EUID:-$(id -u)} -ne 0 ] ; then
  sudo echo "Script can elevate privileges."
  privileged_command_prefix="sudo"
fi

# Get number of cpu cores
num_cpus=$(grep -c ^processor /proc/cpuinfo)

# Download
mkdir -p $temp_dir
cd $temp_dir
extracted_dir=${temp_dir}/spdlog-${version}
if [ ! -e ${extracted_dir} ] ; then
  tar_filename=v${version}.tar.gz
  if [ ! -e ${tar_filename} ] ; then
    curl -fsSL https://github.com/gabime/spdlog/archive/${tar_filename} -o ${tar_filename}
  fi

  tar -xf ${tar_filename}
fi

# Build
cd ${extracted_dir}
mkdir -p build
cd build
cmake -DSPDLOG_FMT_EXTERNAL=ON ..
make -j${num_cpus}

# Check if checkinstall is installed
set +e
command -v checkinstall
checkinstall_installed=$?
set -e

###
# INSTALL
###
deb_pkg_name="${package_name}-${version}"
install_dir="${temp_dir}/${deb_pkg_name}"
mkdir -p "$install_dir"

cmake --install . --prefix "$install_dir/usr"

metadata_dir="${install_dir}/DEBIAN"
mkdir -p "$metadata_dir"

cat <<EOF > "${metadata_dir}/control"
Package: $package_name
Architecture: $(dpkg --print-architecture)
Version: $version
Maintainer: YScope Inc. <dev@yscope.com>
Description: Very fast, header only or compiled, C++ logging library
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