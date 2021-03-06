'''
Copyright (c) 2001-2019 by SAP SE, Walldorf, Germany.
All rights reserved. Confidential and proprietary.
'''

import os
import sys
import json
import re
import utils
import argparse
import shutil
import glob

from os.path import join
from urllib2 import urlopen, Request, quote

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('-m', '--major', help='the SapMachine major version to build', metavar='MAJOR', required=True)
    parser.add_argument('-d', '--destination', help='the download destination', metavar='DIR', required=True)
    args = parser.parse_args()

    major_to_build = int(args.major)
    destination = os.path.realpath(args.destination)
    releases = utils.github_api_request('releases', per_page=100)
    platform = str.format('{0}-{1}_bin', utils.get_system(), utils.get_arch())

    for release in releases:

        if release['prerelease']:
            continue

        version, version_part, major, build_number, sap_build_number, os_ext = utils.sapmachine_tag_components(release['name'])

        if major is None:
            continue

        major = int(major)

        if major <= major_to_build:
            assets = release['assets']

            for asset in assets:
                asset_name = asset['name']
                asset_url = asset['browser_download_url']

                if 'jdk' in asset_name and platform in asset_name and not asset_name.endswith('.txt'):
                    archive_path = join(destination, asset_name)
                    utils.remove_if_exists(archive_path)
                    utils.download_artifact(asset_url, archive_path)
                    boot_jdk_exploded = join(destination, 'boot_jdk')
                    utils.remove_if_exists(boot_jdk_exploded)
                    os.makedirs(boot_jdk_exploded)
                    utils.extract_archive(archive_path, boot_jdk_exploded)

                    sapmachine_folder = glob.glob(join(boot_jdk_exploded, 'sapmachine*'))

                    if sapmachine_folder is not None:
                        sapmachine_folder = sapmachine_folder[0]
                        files = os.listdir(sapmachine_folder)

                        for f in files:
                            shutil.move(join(sapmachine_folder, f), boot_jdk_exploded)

                        utils.remove_if_exists(sapmachine_folder)

                        if utils.get_system() == 'osx':
                            files = os.listdir(join(boot_jdk_exploded, 'Contents', 'Home'))

                            for f in files:
                                shutil.move(join(boot_jdk_exploded, 'Contents', 'Home', f), boot_jdk_exploded)

                            utils.remove_if_exists(join(boot_jdk_exploded, 'Contents'))

                    return 0

    return 0

if __name__ == "__main__":
    sys.exit(main())