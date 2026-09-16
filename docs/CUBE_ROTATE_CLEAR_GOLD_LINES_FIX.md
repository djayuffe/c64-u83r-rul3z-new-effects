# Cube rotation / clear / gold lines fix

## Fixed cube clear

`NewFxPulsePolish` is now disabled while `partId == 3` so the cube owns rows 4..22 completely. The previous shared polish pass could add extra pulse dots after the cube renderer had cleared and redrawn the field, which looked like bad clear/trails.

## Fixed cube rotation

`CvBuildGeometry` is now driven by `CvFrameGeom`, a 16-frame stable geometry table. Each frame defines:

- front left/right/top/bottom
- depth X/Y
- diagonal mode

This removes unstable generated geometry and makes the cube visibly change shape over the rotation cycle without collapsing or reversing line order.

## Fixed cube readability

`CvDrawCorners` and `CvPlotPoint` add bright `+` joints on all front/rear corners so the wireframe reads as a connected 3D object.

## Fixed gold trench lines

Gold Trench now has:

- left `/` rail
- right `\\` rail
- center dotted vanishing line
- beat-synced horizontal gold crossbars
- safe visible line characters only

