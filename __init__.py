# -*- coding: utf-8 -*-
# Copyright (c) 2012, Almar Klein
# This file is distributed under the terms of the (new) BSD License.

""" Package cmu1394

Wraps the CMU driver for 1394 (aka firewire) cameras.
See: http://www.cs.cmu.edu/~iwan/1394/

Use get_cameras() to obtain a list of cameras currently connected. Each
camera instance cen be used to capture frames.

"""

__version__ = 1.1

# Try importing cython compile module from pyzo
try:
    from pyzolib import pyximport
except ImportError:
    pyximport = None

# If we can, see if the module needs to be recompiled
if pyximport:
    ext_kwargs = {'include_dirs':['include'], 'library_dirs': ['lib']}
    pyximport.install(  language='c++', compiler='native',
                        include_dirs=['include'],
                        library_dirs=['lib'], 
                        libraries=['1394camera'] )    

# Import the Cython lib
try:
    from cmu1394 import cmu1394_cython
except ImportError:
    if pyximport is None:
        print('Could not import pyzo.pyximport; cannot compile.')
    else:
        raise

# Inject names into this namespace
get_cameras = cmu1394_cython.get_cameras
Camera = cmu1394_cython.Camera
