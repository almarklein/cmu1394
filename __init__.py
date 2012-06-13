# -*- coding: utf-8 -*-
# Copyright (c) 2012, Almar Klein
# This file is distributed under the terms of the (new) BSD License.

""" Package cmu1394

Wraps the CMU driver for 1394 (aka firewire) cameras.
See: http://www.cs.cmu.edu/~iwan/1394/

Use get_cameras() to obtain a list of cameras currently connected. Each
camera instance cen be used to capture frames.

"""

# Try compiling if pyzo is installed
try:
    from pyzolib import pyximport
except ImportError:
    print('Could not import pyzolib; cannot compile.')
else:
    ext_kwargs = {'include_dirs':['include'], 'library_dirs': ['lib']}
    pyximport.install(  language='c++', compiler='native',
                        include_dirs=['include'],
                        library_dirs=['lib'], 
                        libraries=['1394camera'] )    

# Import 
from . import cmu1394_cython

# Insert names in this namespace
get_cameras = cmu1394_cython.get_cameras
Camera = cmu1394_cython.Camera
