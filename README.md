# cmu1394

(Migrated from code.google.com/p/cmu1394)

The CMU 1394camera driver is an open source driver for firewire cameras on Windows: http://www.cs.cmu.edu/~iwan/1394/

This package wraps this driver using Cython to expose a Python interface to your camera.

## Example

  from cmu1394 import get_cameras
  
  # Get list of currently connected cameras.
  cam_list = get_cameras()
  
  # Get instance of first camera (assuming at least one camera)
  cam = cam_list[0]
  
  # Print description 
  print(cam.description())
  
  # Set format
  cam.set_format('800x600 Mono 8-bit')
  
  # Show the live feed (requires visvis package)
  cam.preview()
