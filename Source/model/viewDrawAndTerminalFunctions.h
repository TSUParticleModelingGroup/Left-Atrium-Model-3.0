#ifndef VIEWDRAWANDTERMINALFUNCTIONS_H
#define VIEWDRAWANDTERMINALFUNCTIONS_H

#include "header.h"
#include <vector>

// prototypes for rendering and view functions

void ShowTooltip(const char*);
void ShowIdentifiedNodesBox();
void ShowIdentifiedMusclesBox();
void renderSphere(float, int, int);
void createSphereVBO(float, int, int);
void renderSphereVBO();
void orthogonalView();
void frustumView();
float4 findCenterOfMass();
void centerObject();
void rotateXAxis(float);
void rotateYAxis(float);
void rotateZAxis(float);
void ReferenceView();
void PAView();
void APView();
void setView(int);
void drawPicture();
void createGUI();
// Reapply node/muscle section colors that were saved in the loaded binary file.
void showMuscleTypes();

#endif // VIEWDRAWANDTERMINALFUNCTIONS_H
