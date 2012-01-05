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
    from pyzo import pyximport
except ImportError:
    print('Could not import pyzo; cannot compile.')
else:
    ext_kwargs = {'include_dirs':['include'], 'library_dirs': ['lib']}
    pyximport.install(  language='c++', compiler='native',
                        include_dirs=['include'], 
                        library_dirs=['lib'], 
                        libraries=['1394camera'] )    

# Import 
from cmu1394 import cmu1394_
get_cameras = cmu1394_.get_cameras
