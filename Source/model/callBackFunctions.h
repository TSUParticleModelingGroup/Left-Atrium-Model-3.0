#ifndef CALLBACKFUNCTIONS_H
#define CALLBACKFUNCTIONS_H

#include "header.h"
#include "viewDrawAndTerminalFunctions.h"
#include "setNodesAndMuscles.h"
#include "cudaFunctions.h"
#include <string>
#include <sstream>

using namespace std;

// prototypes
void reshape(GLFWwindow* window, int width, int height);
int centerMouse(GLFWwindow* window, double* mx, double* my, double* mz);
void mouseFunctionsOff();
void mouseAblateMode();
void mouseEctopicBeatMode();
void mouseEctopicEventMode();
void mouseAdjustMusclesAreaMode();
void mouseAdjustMusclesLineMode();
void mouseIdentifyNodeMode();
void mouseIdentifyMuscleMode();
bool setMouseMuscleAttributes();
void setEctopicBeat(int nodeId);
void clearStdin();
string getTimeStamp();
void movieOn();
void movieOff();
void screenShot();
void saveSettings();
void saveState();
void loadState();
void findNodes();
void hidePulseBackTopNodes();
void KeyPressed(GLFWwindow* window, int key, int scancode, int action, int mods);
void keyHeld(GLFWwindow* window);
void mousePassiveMotionCallback(GLFWwindow* window, double x, double y);
void myMouse(GLFWwindow* window, int button, int action, int mods);
void scrollWheel(GLFWwindow*, double, double);

// helper functions
void identifyMuscleAtIndex(int muscleIndex);

#endif // CALLBACKFUNCTIONS_H
