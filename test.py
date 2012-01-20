#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright (c) 2012, Almar Klein

import cmu1394

print(cmu1394.get_cameras())
cam = cmu1394.get_cameras()[0]

cam.preview()
