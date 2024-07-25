"""Viewport.

Usage:
  viewport streams [--verbose] [--layout=<layout>] <url>...
  viewport [--version] [--help]

Options:
  -v, --verbose      Be verbose.
  --layout=<layout>  The layout to use. Supported layouts are: grid and lms. [Default: grid:3x3]
  <url>              The URL of a live video stream. Supported protocols are: unifi:// and rtsp(s)://.

Example:
    To view all the cameras of an Unifi Protect Controller in a 3x3 equally-spaced grid:
    viewport streams --layout grid:3x3 unifi://username:password@host/_all
"""
from docopt import docopt
import logging
from logger import Logger
from error import ApplicationException
from version import VERSION
from streams import StreamsCommand

if __name__ == '__main__':
    arguments = docopt(__doc__, version="Viewport {version}".format(version=VERSION))

    if arguments['--verbose']:
        Logger.setLevel(logging.DEBUG)

    if arguments["streams"]:
        try:
            streams_command = StreamsCommand(arguments["--layout"], arguments["<url>"])
            # streams_command.run()
        except ApplicationException as e:
            print(e)
            exit(127)

