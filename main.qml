import QtQuick 2.5
import QtQuick.Controls 1.4
import QtQuick.Dialogs 1.2
import QtQuick.Window 2.2

ApplicationWindow {
    visible: true
    width: 640
    height: 480
    title: qsTr("Hello World")
    visibility:"FullScreen"

    Canvas {
        id: windField
        anchors.fill: parent
        //width: 2560, height 1600
        property int robotMaxY: 1600.0 //reset this, for now assume that it is the same as the context dimensions
        // can always scale robot coordinates down later to fit into screen.
        property int robotMaxX: 2560.0 //reset this
        //Right now I have the leaf following whatever the wind flow is, should I add inertia? If so I need
        //a velocity and acceleration of the leaf as well

        //TODO: Create some kind of structure for the leaf/robot
        property double leafX: 200
        property double leafY: 300
        property double leafXV: 0
        property double leafYV: 0
        property double leafXF: 0
        property double leafXY: 0
        property double leafMass: 1
        property double robotSize: 50

        property double pressureToForceMultiplier: 1
        property double pressureTransferRate: .5
        property double maxForce: 10.0

        property double timeStep: .25
        property int numCols: 26
        property int numRows: 16
        property variant pressureGrid: []

        onPaint: {
            var ctx = getContext("2d")
            ctx.strokeStyle = "black"
            ctx.clearRect(0,0, width, height);
            ctx.drawImage("assets/background.jpg", 0,0, width, height)
            drawPressureFields(ctx)
            drawForceVectors(ctx)
            drawLeafVectors(ctx)
            ctx.drawImage("assets/leaf.png", leafX-robotSize/2,leafY-robotSize/2, robotSize, robotSize)
            //console.log("width is", width, "  height is", height)
            //maybe we want this guy outside the canvas for easier manipulation, mouse area, then moving it moves the robot
        }
        /*MouseArea {
            id: fieldInteraction
        }*/

        function initializePressureGrid() {
            var xGridSpacing = (robotMaxX/numCols)
            var yGridSpacing = (robotMaxY/numRows)
            var rows = new Array(numRows)
            for (var i = 0; i < numRows; i++) {
                var column = new Array(numCols)
                for (var j = 0; j < numCols; j++) {
                    var cellArray = new Array(7)
                    cellArray[0] = xGridSpacing/2+j*xGridSpacing //Position X
                    cellArray[1] = yGridSpacing/2+i*yGridSpacing //Position Y
                    cellArray[2] = 0.0 //current wind angle force (for display)
                    cellArray[3] = 0.0 //current wind magnitude force (for display)
                    cellArray[4] = 50.0 //Pressure (from 0 to 100)
                    cellArray[5] = 0.0 //incoming pressure
                    cellArray[6] = 0.0 //Obstacle boolean
                    column[j] = cellArray
                }

                rows[i]=column
            }
            pressureGrid = rows
            setInitialPressures()
        }
        Component.onCompleted: {
            windField.initializePressureGrid()
            loadImage("assets/leaf.png")
        }

        function setInitialPressures() {
            pressureGrid[0][0][4] = 100;
            pressureGrid[15][0][4] = 100.0;
            pressureGrid[0][25][4] = 100.0;
            pressureGrid[15][25][4] = 100.0;

            pressureGrid[7][12][4] = 0.0;
            pressureGrid[8][12][4] = 0.0;
            pressureGrid[7][13][4] = 0.0;
            pressureGrid[8][13][4] = 0.0;

            pressureGrid[13][22][6] = 1;
            pressureGrid[13][23][6] = 1;
            pressureGrid[14][22][6] = 1;
            pressureGrid[14][23][6] = 1;
        }

        //deflections, channels
        //how does speed affect pressure
        //model forces, at each time step take current forces and calculate resulting displacement from timestep

        function updatePressureGrid() {
            //A cell gives up half of the total of the pressure differences (lower) weighted
            //velocity is proportional to this difference
            //it also must factor in existing velocities (a weighted sum of the pressure, which represents mass)

            for (var row = 0; row < numRows; row++) {
                for (var col = 0; col < numCols; col++) {

                    var tempLocalPressure = new Array(3)
                    tempLocalPressure[0] = new Array(3)
                    tempLocalPressure[1] = new Array(3)
                    tempLocalPressure[2] = new Array(3)
                    tempLocalPressure[0][0] = 0.0
                    tempLocalPressure[0][1] = 0.0
                    tempLocalPressure[0][2] = 0.0
                    tempLocalPressure[1][0] = 0.0
                    tempLocalPressure[1][1] = 0.0
                    tempLocalPressure[1][2] = 0.0
                    tempLocalPressure[2][0] = 0.0
                    tempLocalPressure[2][1] = 0.0
                    tempLocalPressure[2][2] = 0.0

                    var numLowPressureNeighbours = 0;
                    var curPressure = pressureGrid[row][col][4]
                    for (var rowOffset = -1; rowOffset <= 1; rowOffset++) {
                        if (row+rowOffset >= numRows || row+rowOffset < 0)
                            continue;
                        for (var colOffset = -1; colOffset <= 1; colOffset++) {
                            var rowIndex = row+rowOffset
                            var colIndex = col+colOffset
                            if ((!rowOffset && !colOffset) || colIndex >= numCols || colIndex < 0 || (pressureGrid[rowIndex][colIndex][6]))
                                continue;
                            var neighbourPressure = pressureGrid[rowIndex][colIndex][4]
                            if (curPressure > neighbourPressure) {
                                var pressureDiff = curPressure - neighbourPressure
                                tempLocalPressure[rowOffset+1][colOffset+1] = pressureDiff
                                numLowPressureNeighbours++
                            } else {
                                tempLocalPressure[rowOffset+1][colOffset+1] = 0.0
                            }
                        }
                    }

                    numLowPressureNeighbours++ //including self
                    for (var i = -1; i <= 1; i++) {
                        for (var j = -1; j <= 1; j++) {
                            var localPressureDiff = pressureTransferRate*tempLocalPressure[i+1][j+1]/numLowPressureNeighbours
                            if (localPressureDiff > 0.0) {
                                pressureGrid[row+i][col+j][5] += localPressureDiff
                                pressureGrid[row][col][5] -= localPressureDiff
                            }
                        }
                    }
                    //Add up differences of all neighbours to get total pressure difference
                    //Update change in pressure accordingly (both negative and positive)
                    //Based on positive pressure flow, add a weight scaled velocity
                }
            }

            for (var row = 0; row < numRows; row++) {
                for (var col = 0; col < numCols; col++) {
                    pressureGrid[row][col][4] += pressureGrid[row][col][5]
                    pressureGrid[row][col][5] = 0.0
                    if (pressureGrid[row][col][6])
                        pressureGrid[row][col][4] = 0.0
                }
            }
        }

        function calculateForceVectors() {
            for (var row = 0; row < numRows; row++) {
                for (var col = 0; col < numCols; col++) {
                    var curPressure = pressureGrid[row][col][4]
                    var validNeighbours = 0
                    var nFX = 0
                    var nFY = 0
                    for (var rowOffset = -1; rowOffset <= 1; rowOffset++) {
                        if (row+rowOffset >= numRows || row+rowOffset < 0)
                            continue;
                        for (var colOffset = -1; colOffset <= 1; colOffset++) {
                            if ((!rowOffset && !colOffset) || col+colOffset >= numCols || col+colOffset < 0 || (pressureGrid[rowIndex][colIndex][6]))
                                continue;
                            var rowIndex = row+rowOffset
                            var colIndex = col+colOffset
                            var pressureDiff = pressureGrid[rowIndex][colIndex][4] - curPressure

                            if (rowOffset != 0 && colOffset == 0) {
                                nFY += rowOffset*pressureDiff
                            } else if (colOffset != 0 && rowOffset == 0) {
                                nFX += -1*colOffset*pressureDiff
                            } else {
                                nFY += rowOffset*Math.SQRT1_2*pressureDiff
                                nFX += -1*colOffset*Math.SQRT1_2*pressureDiff
                            }
                            validNeighbours++
                        }
                    }
                    nFY /= validNeighbours
                    nFX /= validNeighbours

                    pressureGrid[row][col][2] = Math.atan2(nFY, nFX)
                    //TODO: This capped, might want to do something about that
                    pressureGrid[row][col][3] = Math.min(maxForce,Math.sqrt(nFX*nFX+nFY*nFY))
                    //console.log("pressure grid angle: ", pressureGrid[row][col][2], "   magnitude: ", pressureGrid[row][col][3])
                }
            }
        }

        function updateLeaf() {
            //Calculate force acting on the leaf at current pressure conditions
            var xGridSpacing = (robotMaxX/numCols)
            var yGridSpacing = (robotMaxY/numRows)

            //console.log("leafY: ", leafY, "leafX", leafX)
            var rowIndex = Math.floor(leafY/yGridSpacing)
            var colIndex = Math.floor(leafX/xGridSpacing)

            //console.log("Row Index: ", rowIndex, "Col Index: ", colIndex)
            //Pressure is defined as center of the cell, calculate pressure at each corner, be ware of edge conditions
            //TODO: There is a more optimal way to do this, since each corner shares cells, but leaving this for now
            //since this makes it obvious what is going on
            var topLeftPressure = (pressureGrid[Math.max(0,rowIndex-1)][Math.max(0,colIndex-1)][4] +
                                   pressureGrid[Math.max(0,rowIndex-1)][colIndex][4] +
                                   pressureGrid[rowIndex][Math.max(0,colIndex-1)][4] +
                                   pressureGrid[rowIndex][colIndex][4])/
                                  (pressureGrid[Math.max(0,rowIndex-1)][Math.max(0,colIndex-1)][6] +
                                   pressureGrid[Math.max(0,rowIndex-1)][colIndex][6] +
                                   pressureGrid[rowIndex][Math.max(0,colIndex-1)][6] +
                                   pressureGrid[rowIndex][colIndex][6]);
            var topRightPressure = (pressureGrid[Math.max(0,rowIndex-1)][colIndex][4] +
                                    pressureGrid[Math.max(0,rowIndex-1)][Math.min(numCols-1, colIndex+1)][4] +
                                    pressureGrid[rowIndex][colIndex][4] +
                                    pressureGrid[rowIndex][Math.min(numCols-1, colIndex+1)][4])/
                                    (pressureGrid[Math.max(0,rowIndex-1)][colIndex][6] +
                                    pressureGrid[Math.max(0,rowIndex-1)][Math.min(numCols-1, colIndex+1)][6] +
                                    pressureGrid[rowIndex][colIndex][6] +
                                    pressureGrid[rowIndex][Math.min(numCols-1, colIndex+1)][6])
            var bottomLeftPressure = (pressureGrid[rowIndex][Math.max(0,colIndex-1)][4] +
                                      pressureGrid[rowIndex][colIndex] [4]+
                                      pressureGrid[Math.min(numRows-1,rowIndex+1)][Math.max(0,colIndex-1)][4] +
                                      pressureGrid[Math.min(numRows-1,rowIndex+1)][colIndex][4])/
                                     (pressureGrid[rowIndex][Math.max(0,colIndex-1)][6] +
                                      pressureGrid[rowIndex][colIndex][6]+
                                      pressureGrid[Math.min(numRows-1,rowIndex+1)][Math.max(0,colIndex-1)][6] +
                                      pressureGrid[Math.min(numRows-1,rowIndex+1)][colIndex][6])
            var bottomRightPressure = (pressureGrid[rowIndex][colIndex][4] +
                                       pressureGrid[rowIndex][Math.min(numCols-1, colIndex+1)][4] +
                                       pressureGrid[Math.min(numRows-1,rowIndex+1)][colIndex][4] +
                                       pressureGrid[Math.min(numRows-1,rowIndex+1)][Math.min(numCols-1, colIndex+1)][4])/
                                      (pressureGrid[rowIndex][colIndex][6] +
                                       pressureGrid[rowIndex][Math.min(numCols-1, colIndex+1)][6] +
                                       pressureGrid[Math.min(numRows-1,rowIndex+1)][colIndex][6] +
                                       pressureGrid[Math.min(numRows-1,rowIndex+1)][Math.min(numCols-1, colIndex+1)][6])
            //console.log("TL: ", topLeftPressure, "TR: ", topRightPressure, "BL: ", bottomLeftPressure, "BR: ", bottomRightPressure)

            //Now interpolate between the points to find the force (which we will just call the
            var xRatio = (leafX-colIndex*xGridSpacing)/xGridSpacing
            var topPressure = topLeftPressure+(topRightPressure-topLeftPressure)*xRatio
            var bottomPressure = bottomLeftPressure+(bottomRightPressure-bottomLeftPressure)*xRatio

            var yRatio = (leafY-rowIndex*yGridSpacing)/yGridSpacing
            var leftPressure = topLeftPressure+(bottomLeftPressure-topLeftPressure)*yRatio
            var rightPressure = topRightPressure+(bottomRightPressure-topRightPressure)*yRatio
            //console.log("Top: ", topPressure, "Bot: ", bottomPressure, "Left: ", leftPressure, "Right: ", rightPressure)

            //TODO: Gradient is pressure/dist, treating dist as just 1 for now
            var forceY = (topPressure-bottomPressure)*pressureToForceMultiplier
            var forceX = (leftPressure-rightPressure)*pressureToForceMultiplier
            //console.log("Forces: ", forceX, " ", forceY)

            //update position from one time step given current velocity and current force
            var deltaX = leafXV*timeStep+.5*forceX/leafMass*timeStep*timeStep
            var deltaY = leafYV*timeStep+.5*forceY/leafMass*timeStep*timeStep
            leafXV += forceX/leafMass*timeStep
            leafYV += forceY/leafMass*timeStep
            leafX += deltaX
            leafY += deltaY
            if (leafX > robotMaxX-robotSize/2 || leafX < 0) {
                leafXV = 0;
                leafX = Math.max(Math.min(leafX, robotMaxX-robotSize/2), 0.0)
            } else if (leafY > robotMaxY-robotSize/2 || leafY < 0) {
                leafYV = 0;
                leafY = Math.max(Math.min(leafY, robotMaxY-robotSize/2), 0.0)
            }
        }

        function drawPressureFields(ctx) {
            var xGridSpacing = (robotMaxX/numCols)
            var yGridSpacing = (robotMaxY/numRows)
            for (var row = 0; row < numRows; row++) {
                for (var col = 0; col < numCols; col++) {
                    if (pressureGrid[row][col][6]) {
                        ctx.fillStyle = 'black'
                    } else {
                        var pressure = pressureGrid[row][col][4];
                        ctx.fillStyle = Qt.rgba(pressure/100.0, 0, (100-pressure)/100.0, .75)
                    }
                    ctx.fillRect(col*xGridSpacing,row*yGridSpacing,xGridSpacing,yGridSpacing)
                }
            }
        }

        function drawLeafVectors(ctx) {
            // Draw velocity vector
            var windVelocityX = leafXV*5
            var windVelocityY = leafYV*5
            ctx.strokeStyle = "white"
            ctx.fillStyle = "white"
            ctx.lineWidth = Math.min(robotSize, Math.sqrt(leafXV*leafXV+leafYV*leafYV))
            ctx.beginPath()
            ctx.moveTo(leafX, leafY)
            ctx.lineTo(leafX+windVelocityX, leafY+windVelocityY)
            ctx.stroke()

            var perpVecX = -windVelocityY
            var perpVecY = windVelocityX

            ctx.beginPath()
            ctx.moveTo(leafX+windVelocityX*1.1, leafY+windVelocityY*1.1)
            ctx.lineTo(leafX+windVelocityX*.75+perpVecX*.33, leafY+windVelocityY*.75+perpVecY*.33)
            ctx.lineTo(leafX+windVelocityX*.75-perpVecX*.33, leafY+windVelocityY*.75-perpVecY*.33)
            ctx.closePath()
            ctx.fill()

            //draw force vector
            var forceDirection = pressureGrid[row][col][2]
            var forceMagnitude = pressureGrid[row][col][3]
            ctx.strokeStyle = "white"
            ctx.fillStyle = "white"
            ctx.lineWidth = Math.max(1,5*forceMagnitude/maxForce)

            var windVectorX = xGridSpacing/2*Math.cos(forceDirection)*forceMagnitude/maxForce
            var windVectorY = -xGridSpacing/2*Math.sin(forceDirection)*forceMagnitude/maxForce
            var centerX = xGridSpacing/2+col*xGridSpacing;
            var centerY = yGridSpacing/2+row*yGridSpacing;
            ctx.beginPath()
            ctx.moveTo(centerX, centerY)
            ctx.lineTo(centerX+windVectorX, centerY+windVectorY)
            ctx.stroke()

            var perpVecX = -windVectorY
            var perpVecY = windVectorX

            ctx.beginPath()
            ctx.moveTo(centerX+windVectorX, centerY+windVectorY)
            ctx.lineTo(centerX+windVectorX*.75+perpVecX*.33, centerY+windVectorY*.75+perpVecY*.33)
            ctx.lineTo(centerX+windVectorX*.75-perpVecX*.33, centerY+windVectorY*.75-perpVecY*.33)
            ctx.closePath()
            ctx.fill()
        }

        function drawForceVectors(ctx) {
            var xGridSpacing = (robotMaxX/numCols)
            var yGridSpacing = (robotMaxY/numRows)
            ctx.strokeStyle = "black"
            ctx.fillStyle = 'black'
            for (var row = 0; row < numRows; row++) {
                for (var col = 0; col < numCols; col++) {
                    var forceDirection = pressureGrid[row][col][2]
                    var forceMagnitude = pressureGrid[row][col][3]
                    ctx.lineWidth = Math.max(1,5*forceMagnitude/maxForce)

                    var windVectorX = xGridSpacing/2*Math.cos(forceDirection)*forceMagnitude/maxForce
                    var windVectorY = -xGridSpacing/2*Math.sin(forceDirection)*forceMagnitude/maxForce
                    var centerX = xGridSpacing/2+col*xGridSpacing;
                    var centerY = yGridSpacing/2+row*yGridSpacing;
                    ctx.beginPath()
                    ctx.moveTo(centerX, centerY)
                    ctx.lineTo(centerX+windVectorX, centerY+windVectorY)
                    ctx.stroke()

                    var perpVecX = -windVectorY
                    var perpVecY = windVectorX

                    ctx.beginPath()
                    ctx.moveTo(centerX+windVectorX, centerY+windVectorY)
                    ctx.lineTo(centerX+windVectorX*.75+perpVecX*.33, centerY+windVectorY*.75+perpVecY*.33)
                    ctx.lineTo(centerX+windVectorX*.75-perpVecX*.33, centerY+windVectorY*.75-perpVecY*.33)
                    ctx.closePath()
                    ctx.fill()
                }
            }
        }

        function updateField() {
            setInitialPressures()
            calculateForceVectors() //TOOD: Only do this if enabled, takes a lot of extra calculation
            updateLeaf()
            updatePressureGrid()
            requestPaint()
        }

        Timer {
            id: paintTimer
            interval: 15
            repeat: true
            running: true
            triggeredOnStart: true
            onTriggered: windField.updateField()
        }
    }
}

