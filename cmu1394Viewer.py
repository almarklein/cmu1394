""" Endothelial cell detector.
"""

from PyQt4 import QtGui, QtCore
import cmu1394
import sys, os, time

import visvis as vv
app = vv.use('qt4')


class SideBar(QtGui.QWidget):
    
    def __init__(self, *args):
        QtGui.QWidget.__init__(self, *args)
        
        # Limit width
        self.setMinimumWidth(250)
        self.setMaximumWidth(250)
        
        # Create refresh button
        self._butRefreshCameraList = QtGui.QPushButton('Refresh camera list', self)
        self._butRefreshCameraList.pressed.connect(self.refreshCameraList)
        
        # Create list of cameras
        self._listCameras = QtGui.QComboBox(self)
        self._listCameras.activated.connect(self.activateCamera)
        
        # Create list for resolutions
        self._listFormats = QtGui.QComboBox(self)
        self._listFormats.activated.connect(self.activateFormat)
        
        # Create label for fps
        self._labelFps = QtGui.QLabel(self)
        
        # Layout
        layout = QtGui.QVBoxLayout()
        layout.addWidget(self._butRefreshCameraList)
        layout.addWidget(self._listCameras)
        layout.addWidget(self._listFormats)
        layout.addWidget(self._labelFps)
        layout.addStretch(1)
        self.setLayout(layout)
        
        # Start timer
        self._timer = QtCore.QTimer(self)
        self._timer.timeout.connect(self.onTimerTimeout)
        self._timer.setSingleShot(False)
        self._timer.start(200)
        
        # Finish
        self._theCam = None
        self._texture = None
        self.refreshCameraList()
    
    
    def onTimerTimeout(self):
        """ onTimerTimeout()
        
        Is called every once in a while to show an image of the camera.
        
        """
        
        # Is there even a camea?
        if not self._theCam:
            return
        
        # Get data
        im = self._theCam.get_data()
        
        # Show
        if not self._texture:
            self.parent()._fig.MakeCurrent()
            vv.clf()
            self._texture = vv.imshow(im)
            a = self._texture.GetAxes()
            a.axis.visible = False
        else:
            self._texture.SetData(im)
    
    
    def refreshCameraList(self):
        """ refreshCameraList()
        
        Refreshes the camera list.
        
        """
        
        # Init
        cams = cmu1394.get_cameras()
        self._listCameras.clear()
        self._listCameras._cams = cams
        
        if cams:
            self._listCameras.addItem('<No camera (%i available)>' % len(cams))
            for cam in cams:
                description = cam.description()
                name = description.rsplit(' ',1)[0]
                self._listCameras.addItem(description)
        else:
            self._listCameras.addItem('<No cameras detected>')
        
        # Reset
        self.activateCamera(0)
    
    
    def activateCamera(self, index):
        """ activateCamera(index)
        
        Select a camera to be the current.
        
        """
        
        # First stop the current camera
        if self._theCam:
            self._theCam.stop()
        
        # Clear the figure
        self.parent()._fig.Clear()
        self._texture = None
        
        # Select the camera
        if index == 0:
            self._theCam = None
        else:
            self._theCam = self._listCameras._cams[index-1]
        
        # Reset resolutions
        self.refreshFormatList()
    
    
    def refreshFormatList(self):
        
        # Init        
        self._listFormats.clear()
        
        if self._theCam:
            # Get formats and current
            formats = self._theCam.supported_formats()
            theFormat = self._theCam.format()
            # Sort
            def sorter(a,b):
                axy = a.split(' ')[0].split('x')
                an = int(axy[0]) * int(axy[1])
                bxy = b.split(' ')[0].split('x')
                bn = int(bxy[0]) * int(bxy[1])
                if an==bn:
                    return [-1,1][a>b]
                else:
                    return [-1,1][an>bn]
            formats.sort(cmp=sorter)
            # List
            for format in formats:
                self._listFormats.addItem(format)
                if format == theFormat: # Make current
                    self._listFormats.setCurrentIndex(self._listFormats.count()-1)
        else:
            self._listFormats.addItem('<No camera selected>')
        
        self.setFrameRate()
    
    
    def activateFormat(self, index):
        """ activateFormat(index)
        
        Select resolution for the camera.
        
        """
        
        # Check
        if not self._theCam:
            self.refreshFormatList()
            return 
            
        # Get format and set
        format = str(self._listFormats.itemText(index))
        self._theCam.set_format(format)
        
        # Force a redraw
        self._texture = None
        
        # Set frame rate
        self.setFrameRate()
    
    
    def setFrameRate(self):
        """ setFrameRate()
        
        Show the current frame rate.
        
        """
        if self._theCam:
            
            # Get maximal fps (or 30)
            fpss = self._theCam.supported_framerates()
            if 30 in fpss:
                fps = 30
            else:
                fps = max(fpss)
            # Set
            self._theCam.set_framerate(fps)
            self._labelFps.setText('%i fps' % fps)
        
        else:
            self._labelFps.setText('0 fps')



class MainWindow(QtGui.QWidget):
    
    def __init__(self):
        QtGui.QWidget.__init__(self)
        
        # Limit size
        self.setMinimumHeight(500)
        self.setMinimumWidth(600)
        
        # Make figure using "self" as a parent
        self._fig = vv.backends.backend_qt4.Figure(self)
        
        # Create sidebar
        self._sidebar = SideBar(self)
        
        # Layout
        layout = QtGui.QHBoxLayout()
        layout.addWidget(self._sidebar, 0)
        layout.addWidget(self._fig._widget, 1)
        self.setLayout(layout)
        
        # Finish
        self.setWindowTitle('Endothelial Cells Detector')
        self.show()


# Run the visvis way. Will run in interactive mode when used in IEP or IPython.
app.Create()
m = MainWindow()
app.Run()
