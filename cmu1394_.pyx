# -*- coding: utf-8 -*-
# Copyright (c) 2012, Almar Klein
# This file is distributed under the terms of the (new) BSD License.

""" Cython module cmu1394_

Wraps the CMU driver for 1394 (aka firewire) cameras.
See: http://www.cs.cmu.edu/~iwan/1394/

"""

# Python imports
import time
import numpy as np

# Cython specific imports
cimport numpy as np
import cython 

# Put this in first to avoid all the weird syntax errors
cdef extern from "windows.h":
    pass

# Enable low level memory management
cdef extern from "stdlib.h":
   void free(void* ptr)
   void* malloc(size_t size)

# Include cmu driver. We only need the C1394Camera class
cdef extern from "include/1394Camera.h":
    cdef cppclass C1394Camera:
        
        # Control
        #int CheckLink() # deprecated 
        int RefreshCameraList()
        int SelectCamera(int)
        int InitCamera(int)
        int IsInitialized() # todo: use this to reduce wait time?
        int IsAcquiring()
        unsigned long GetVersion()
        int GetNumberCameras()
        int GetNode()
        int GetNodeDescription(int, char*, int)
        #int StartVideoStream()
        #int StopVideoStream()
        #int HasOneShot()
        #int OneShot()
        #int HasMultiShot()
        #int MultiShot ()
        #bool InitResources ()
        #bool FreeResources ()
        
        # Acquisition
        int StartImageAcquisition()
        int AcquireImage()
        int StopImageAcquisition()
        unsigned char* GetRawData(unsigned long*)
        int getRGB(unsigned char*, unsigned long)
        
        # Video Format Control
        int SetVideoFormat(unsigned long)
        int SetVideoMode(unsigned long)
        int SetVideoFrameRate(unsigned long)
        #
        int HasVideoMode(unsigned long, unsigned long)
        int HasVideoFrameRate(unsigned long, unsigned long, unsigned long)
        #
        int GetVideoFormat()
        int GetVideoMode()
        int GetVideoFrameRate()
        #
        void GetVideoFrameDimensions(unsigned long*, unsigned long*)


## Maps for errors
CAM_SUCCESS = 0
CAM_ERROR = -1
CAM_ERROR_UNSUPPORTED = -10
CAM_ERROR_NOT_INITIALIZED = -11
CAM_ERROR_INVALID_VIDEO_SETTINGS = -12
CAM_ERROR_BUSY = -13
CAM_ERROR_INSUFFICIENT_RESOURCES = -14
CAM_ERROR_PARAM_OUT_OF_RANGE = -15
CAM_ERROR_FRAME_TIMEOUT = -16

# Map errors to messages
ERRORMAP = {
   CAM_ERROR: 'CAM_ERROR: This error typically indicates some problem from the Windows I/O subsystem.',
   CAM_ERROR_UNSUPPORTED: 'CAM_ERROR_UNSUPPORTED: The feature implied by the called function (e.g. SetPIOOutputBits()) is not supported.',
   CAM_ERROR_NOT_INITIALIZED: 'CAM_ERROR_NOT_INITIALIZED: The camera is not properly initialized.',
   CAM_ERROR_INVALID_VIDEO_SETTINGS: 'CAM_ERROR_INVALID_VIDEO_SETTINGS: The selected video settings are unsupported.',
   CAM_ERROR_BUSY: 'CAM_ERROR_BUSY: Many functions are disallowed while acquiring images, you must call StopImageAcquisition() first.',
   CAM_ERROR_INSUFFICIENT_RESOURCES: 'CAM_ERROR_INSUFFICIENT_RESOURCES: Insufficient memory or bus bandwidth is available to complete the request.',
   CAM_ERROR_PARAM_OUT_OF_RANGE: 'CAM_ERROR_PARAM_OUT_OF_RANGE: Many parameters have bounds, one of them has been exceeded.',
   CAM_ERROR_FRAME_TIMEOUT: 'CAM_ERROR_FRAME_TIMEOUT: Returned by AcquireImageEx() to indicate that the timeout has expired and no frame is ready.',
}

cdef getError(err, extra=''):
    if err == CAM_SUCCESS:
        return
    if err in ERRORMAP:
        msg = ERRORMAP[err]
    elif err:
        msg = 'Unkown error (%i).' % err
    if extra:
        msg += extra
    return msg

cdef raiseIfError(err, extra=''):
    msg = getError(err, extra)
    if msg:
        raise CameraError(msg)


class CameraError(RuntimeError):
    pass


## Maps for format and frame rate

# Maps FPS index to frame rate in frames/second
INT2FPS = [1.875, 3.75, 7.5, 15, 30, 60, 120, 240]

# Maps a string to (format,mode) tuple
FORMATS = { 
    "160x120 YUV(4:4:4)":   (0,0),
    "320x240 YUV(4:2:2)":   (0,1),
    "640x480 YUV(4:1:1)":   (0,2),
    "640x480 YUV(4:2:2)":   (0,3),
    "640x480 RGB":          (0,4),
    "640x480 Mono (8-bit)": (0,5),
    "640x480 Mono (16-bit)":(0,6),
    #
    "800x600 YUV(4:2:2)":   (1,0),
    "800x600 RGB":          (1,1),
    "800x600 Mono (8-bit)": (1,2),
    "1024x768 YUV(4:2:2)":  (1,3),
    "1024x768 RGB":         (1,4),
    "1024x768 Mono (8-bit)":(1,5),
    "800x600 Mono (16-bit)":(1,6),
    "1024x768 Mono (16-bit)":(1,7),
    #
    "1280x960 YUV(4:2:2)":  (2,0),
    "1280x960 RGB":         (2,1),
    "1280x960 Mono (8-bit)":(2,2),
    "1600x1200 YUV(4:2:2)": (2,3),
    "1600x1200 RGB":        (2,4),
    "1600x1200 Mono (8-bit)":(2,5),
    "1280x960 Mono (16-bit)":(2,6),
    "1600x1200 Mono (16-bit)":(2,7),
}


## Implementation

# Create Base camera object. We can use this to query global stuff.
cdef C1394Camera _BaseCamera

# Create dictionary to hold all specific cameras.
# This is done so that every hardware-camera maps to a unique Camera instance.
_CAMERAS = {}


cdef _get_camera_name(index):
    # Prepare writable string buffer
    cdef bytes str_buf = ('x'*256).encode('utf-8')
    cdef char* c_string = str_buf    
    # Let CMU write to it
    length = _BaseCamera.GetNodeDescription(index, c_string, len(str_buf))
    if length:
        return str_buf[:length].decode('utf-8')
    else:
        return ''


def get_cameras():
    """ get_cameras()
    
    Get a list of Camera instances currently available.
    
    """
    
    # Get how many are currently connected
    n = _BaseCamera.RefreshCameraList()
    if n < 0:
        raise CameraError(getError(n, 'Could not list cameras.'))
    
    # Create (or reuse) Camera instance for each hardware-camera
    new_cameras = {}
    for i in range(n):
        name = _get_camera_name(i)
        key = (i, name)
        if key in _CAMERAS:
            new_cameras[key] = _CAMERAS[key]
        else:
            new_cameras[key] = Camera(i)
    
    # Update _CAMERAS
    _CAMERAS.clear()
    _CAMERAS.update(new_cameras)
    new_cameras.clear()
    
    # Return as a list
    return _CAMERAS.values()


cdef class Camera:
    """ Camera(index)
    
    Notice: users should not create instances of this class, but use
    get_cameras() to obtain a list of instances.
    
    Every Camera instance maps to one harware camera. Using this object
    the user can grab frames (get_data()). Settings can be changed
    using set_format() and set_framerate().
    
    """
    
    cdef C1394Camera *camera
    cdef int index
    
    def __init__(self, index):
        
        # Store index        
        self.index = index
        self.camera = new C1394Camera()
        
        # Check if camera is connected
        res = self.camera.RefreshCameraList()
        if res < 0:
            raiseIfError(res, 'Could not detect cameras.')
        if (index+1) > res:
            raise CameraError('Not a valid camera index.')
        
        # Select camera
        self.camera.SelectCamera(index)
        
        # Try initializing        
        raiseIfError(self.camera.InitCamera(1), 'Camera initialization failed.')
        
        
        # Try setting video format
        if self.camera.SetVideoFormat(0) != CAM_SUCCESS:
            print('Camera could not set video format.')
            return
        
        # Try setting video mode
        if self.camera.SetVideoMode(5) != CAM_SUCCESS:
            print('Camera could not set video mode.')
            return
        
        # Try setting framerate
        if self.camera.SetVideoFrameRate(4) != CAM_SUCCESS:
            print('Camera could not set framerate.')
            return
    
    
    def __dealloc__(self):
        # Stop acquisition if running
        if self.camera.IsAcquiring():
            self.camera.StopImageAcquisition()
        del self.camera
    
    
    ## Misc stuff
    
    def __repr__(self):
        return "<Camera %s>" % self.description()
    
    
    def description(self):
        """ description()
        Get the manufacturer, model name, and device id as a string.
        """
        return _get_camera_name(self.index)
    
    
    def device_id(self):
        """ device_id()
        Get the id (i.e. index) of this camera.
        """
        return self.index
    
    
    ## Settings
    
    def supported_formats(self):
        """ supported_formats()
        Get a list of supported formats as strings.
        """
        formats = []
        for format in FORMATS:
            form, mode = FORMATS[format]
            if self.camera.HasVideoMode(form, mode):
                formats.append(format)
        return formats
    
    
    def format(self):
        """ format()
        Get the current format.
        """
        # Get current format
        form_, mode_ = self.camera.GetVideoFormat(), self.camera.GetVideoMode()
        
        # Search string that describes it
        for format in FORMATS:
            form, mode = FORMATS[format]
            if form == form_ and mode == mode_:
                return format
        else:
            raise CameraError('Could not detect format.')
    
    
    def set_format(self, value):
        """ set_format(value)
        
        Set the format to use. This will stop() the camera if it is currently
        on.
        
        This method is quite flexible: the given value is split in pieces 
        (using space as a dilimiter). Next, the format is selected that 
        has all pieces in it. 
        
        """
        # Make sure the camera is off
        self.stop()
        
        # Check values
        values = [val.lower() for val in value.split(' ')]
        for val in values:
            if len(val) < 3:
                raise ValueError('Invalid format description: %s.' % value)
        
        # Get supported formats
        formats = self.supported_formats()
        
        # Get matches for each value
        sets = []
        for val in values:
            S = set()
            for format in formats:
                if val in format.lower():
                    S.add(format)
            sets.append(S)
        
        # Get format that is in all sets
        S = set.intersection(*sets)
        
        # Test
        if len(S) == 0:
            raise ValueError('The given format is not supported.')
        elif len(S) > 1:
            raise ValueError('The given format description is ambigious.')
        else:
            # Set this format
            form, mode = FORMATS[S.pop()]
            raiseIfError(self.camera.SetVideoFormat(form))
            raiseIfError(self.camera.SetVideoMode(mode))
    
    
    def supported_framerates(self):
        """ supported_framerates()
        Get all supported framerates (for the current format). In general, lower 
        resolutions allow higher framerates. Returns a list of floats.
        """
        # Get current format
        form, mode = self.camera.GetVideoFormat(), self.camera.GetVideoMode()
        
        # Get rates
        rates = []        
        for i in range(len(INT2FPS)):
            rate = INT2FPS[i]
            if self.camera.HasVideoFrameRate(form, mode, i):
                rates.append(rate)
        
        # Done
        return rates
    
    
    def framerate(self):
        """ framerate()
        Get the current framerate.
        """
        return INT2FPS[self.camera.GetVideoFrameRate()]
    
    
    def set_framerate(self, rate):
        """ set_framerate(value)
        Set the framerate. Accepts floats and strings. This will stop() 
        the camera if it is currently on.
        
        """
        
        # Make sure the camera is off
        self.stop()
        
        # Make float
        if isinstance(rate, basestring):
            rate = rate.split(' ')[0] # remove 'fps' part if present
        rate = float(rate)
        
        # Convert to framerate id and set
        for i in range(len(INT2FPS)):
            if rate == INT2FPS[i]:
                raiseIfError(self.camera.SetVideoFrameRate(i))
                break
        else:
            ValueError('Invalid framerate given.')
    
    
    ## Acquisition
    
    def start(self):
        """ start()        
        Turn the camera on. This means the camera is taking pictures, and
        get_data() can be used to capture them.
        """
        # Make it safe to start camera multiple times
        if self.camera.IsAcquiring():
            return
        
        # Try starting acquisition
        raiseIfError(   self.camera.StartImageAcquisition(), 
                        'Camera could not start image acquisition.' )
        
        # Give camera time to init
        time.sleep(0.5)
    
    
    def stop(self):
        """ stop()
        Turn the camera off.
        """
        # Make it safe to stop camera multiple times
        if not self.camera.IsAcquiring():
            return
        
        # Stop acquisition
        res = self.camera.StopImageAcquisition()
        if res < 0:
            print(getError(res))
    
    
    def is_on(self):
        """ is_on()
        Returns True if the camera is now on. Returns False otherwise.
        """
        return bool(self.camera.IsAcquiring())
    
    
    def get_data(self):
        """ get_data()
        
        Capture a frame from the camera. This will start() the camera if it
        is currently off.
        
        Use set_format() to change the resolution. Use set_framerate() 
        to change the speed with which frames can be grabbed.
        
        """
        
        # Make sure the camera is on
        self.start()
        
        # Capture frame
        raiseIfError(self.camera.AcquireImage(), 'Camera could not acquire image.')
        
        # Get dimensions
        cdef unsigned long w = 0
        cdef unsigned long h = 0
        self.camera.GetVideoFrameDimensions(&w, &h)
        #print 'dimensions', w,h
        
        # Get pointer to data and length
        cdef unsigned long pLength = 0
        cdef unsigned char *pData = self.camera.GetRawData(&pLength)
        if pLength == 0:
            raise CameraError('Could not get data from camera.')
        
        # Determine shape and datatype of the data
        if w*h == pLength:
            shape, dtype = (h,w), 'uint8' # HxW Mono 8-bit
        elif w*h*2 == pLength:
            shape, dtype = (h,w), 'uint16' # HxW Mono 16-bit
        elif w*h*3 == pLength:
            shape, dtype = (h,w,3), 'uint8' # HxW RGB
        else:
            raise RuntimeError('Could not determine shape of the data. Use other format or use get_rgb().')
        
        # Create empty numpy array for holding the data
        n = reduce(lambda x,y: x*y, shape)
        cdef np.ndarray[np.uint8_t] im = np.empty((pLength,), 'uint8')
        
        # Copy data from camera buffer to numpy array
        cdef int i
        cdef int imax = <int>pLength
        cdef unsigned char* pData2 = <unsigned char*>im.data
        for i in range(imax):
            pData2[i] = pData[i]
        
        # Set shape, also convert to uint16 if needed
        if dtype == 'uint16':
            # Convert endianness
            im2 = np.frombuffer(im, '>u2', n).astype(dtype)
        else:
            im2 = im.view()
        im2.shape = shape
        
        return im2
    
    
    def get_rgb(self):
        """ get_rgb()
        
        Capture a frame from the camera. This will start() the camera if it
        is currently off.
        
        This method is similar to get_data(), but always returns an RGB
        image. The conversion is done by the underlying CMU 1394camera
        driver. Therefore this method might work in for formats where 
        get_data() does not work.
        
        Use set_format() to change the resolution. Use set_framerate() 
        to change the speed with which frames can be grabbed.
        
        """
        
        # Make sure the camera is on
        self.start()
        
        # Capture frame
        raiseIfError(self.camera.AcquireImage(), 'Camera could not acquire image.')
        
        # Get dimensions
        cdef unsigned long w = 0
        cdef unsigned long h = 0
        self.camera.GetVideoFrameDimensions(&w, &h)
        #print 'dimensions', w,h
        
        # Determine shape and datatype of the data        
        shape, dtype = (h,w,3), 'uint8'
        
        # Get numpy array with the data
        cdef np.ndarray[np.uint8_t,ndim=3] im = np.zeros(shape, dtype)
        self.camera.getRGB(<unsigned char*>im.data, im.size)
        
        return im
    
    
    def preview(self):
        """ preview()
        
        Show a live feed of the camera. This opens a figure in which
        the feed is displayed. This method returns when the figure window
        is closed.
        
        Requires visvis.
        
        """
        
        # Make sure the camera is on
        self.start()
        
        # Import time and visvis
        import time
        import visvis as vv
        
        # Create figure and init 
        fig = vv.figure()
        t = vv.imshow(self.get_data())
        t.GetAxes().axis.visible = False
        
        # Enter main loop until figure is closed
        while fig.children:
            time.sleep(0.001)
            t.SetData(self.get_data())
            vv.processEvents()
