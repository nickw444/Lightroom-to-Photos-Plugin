#!/usr/bin/env python3
import concurrent
import multiprocessing
import shutil
from concurrent.futures import ProcessPoolExecutor
from fnmatch import fnmatch
from multiprocessing import Semaphore

import click
import glob
import os
from wand.image import Image
import tomllib

"""
TODO:
 - Support for include-event (e.g. 2022-02-02)
 - Install to PATH
 - Move LRE to Edits/
 - Dont copy original JPEG if direct LRE version exists (by flag)
 - Folder level overrides:
    - Exclusions
    - Allow copy original & LRE JPEG
"""

DEFAULT_CONFIG_FILE_PATH = os.path.expanduser('~/.syncpics')


@click.command
@click.option('--config-file', type=click.File('rb'), default=DEFAULT_CONFIG_FILE_PATH)
@click.option('--include', type=str, default='**/*')
@click.option('--include-event', type=str)
@click.option('--dryrun', is_flag=True)
def syncpics(config_file, include, include_event, dryrun):
    """
    Extract camera JPEGs from Lightroom hierarchy, convert to HEIC, and output to
    mirrored directory tree, ready for import into Apple Photos.
    """

    config = tomllib.load(config_file)['syncpics']
    source = config['source']
    destination = config['destination']
    excludes = []

    if 'excludes' in config:
        excludes = [exl.strip() for exl in config['excludes']]

    workers = multiprocessing.cpu_count() - 1
    sem = Semaphore(workers)
    with ProcessPoolExecutor(max_workers=workers) as executor, click.progressbar(
            glob.glob(os.path.join(source, include), recursive=True)) as bar:
        for file in bar:
            if os.path.isdir(file):
                continue

            if is_excluded(excludes, os.path.relpath(file, source)):
                continue

            basename, ext = os.path.splitext(os.path.basename(file))
            if ext.upper() in ('.JPG', '.JPEG'):
                # Perform conversion into new hierarchy location.
                destination_dir = os.path.join(destination, os.path.relpath(os.path.dirname(file), source))
                if not dryrun and not os.path.exists(destination_dir):
                    os.makedirs(destination_dir)

                destination_path = os.path.join(destination_dir, f'{basename}.HEIC')
                if os.path.exists(destination_path):
                    continue

                if not dryrun:
                    sem.acquire()
                    job = executor.submit(convert_to_heic, file, destination_path)
                    job.add_done_callback(lambda _: sem.release())

                click.echo("{} -> {}".format(
                    os.path.relpath(file, source),
                    os.path.relpath(destination_path, destination)
                ))

            elif ext.upper() in ('.MOV', '.MP4'):
                # Perform verbatim copy for import into Apple Photos
                # Check exists in destination first.
                destination_dir = os.path.join(destination, os.path.relpath(os.path.dirname(file), source))
                if not dryrun and not os.path.exists(destination_dir):
                    os.makedirs(destination_dir)

                destination_path = os.path.join(destination_dir, os.path.basename(file))
                if os.path.exists(destination_path):
                    continue

                if not dryrun:
                    shutil.copyfile(file, destination_path)

                click.echo("{} -> {}".format(
                    os.path.relpath(file, source),
                    os.path.relpath(destination_path, destination)
                ))

            elif ext.upper() in ('.CR3', '.DNG', '.XMP'):
                # Check for corresponding exported JPG
                continue
            else:
                raise AssertionError('Unhandled format for: ' + file)


def is_excluded(excludes, file):
    for exclude in excludes:
        if fnmatch(file, exclude):
            return True

    return False


def convert_to_heic(source: str, destination: str):
    with Image(filename=source) as img:
        img.format = 'heic'
        img.save(filename=destination)


if __name__ == '__main__':
    syncpics()
