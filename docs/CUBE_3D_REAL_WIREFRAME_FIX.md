# Cube 3D real wireframe fix

The previous `cv_update` renderer was only a 16-point rotor placeholder.  It did not draw connected cube edges and only cleared four rows, so it could look broken, invisible, or leave trails.

## Fixed

`CUBE V3 ROTOR FINAL` now draws a real text-mode 3D wire cube every frame:

- full field clear on rows 4..22
- front square
- rear square
- four depth connectors
- beat/pulse colour response
- dynamic inset/offset for rotate/zoom illusion
- row 24 stays protected for the global scroller

## New cube helpers

- `CvBuildGeometry`
- `CvDrawWireCube`
- `CvHLine`
- `CvVLine`
- `CvDiagLine`
- `CvInsetTbl`
- `CvDepthX`
- `CvDepthY`

The audit now fails if the old point-placeholder renderer returns.
