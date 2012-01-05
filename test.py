
import cmu1394

print(cmu1394.get_cameras())
cam = cmu1394.get_cameras()[0]

cam.preview()
 