#ifndef SETNODESANDMUSCLES_H
#define SETNODESANDMUSCLES_H

#include "header.h"
#include "cudaFunctions.h"  // for cudaErrorCheck
#include "viewDrawAndTerminalFunctions.h"  // for setView

// prototypes for functions that read/setup node and muscle data

void readNodesFromFile();
void centerNodes();
void checkNodes();
void readPulseUpAndFrontNodesFromFile();
void readBachmannBundleFromFile();
void readAndConnectMusclesFromFile();
void readNodesAndMusclesFromBinaryFile();
void linkNodesToMuscles();
double croppedRandomNumber(double, double, double);
void findRadiusAndMassOfLeftAtrium();
void setRemainingNodeAndMuscleAttributes();
void getNodesandMusclesFromPreviousRun();
void setRemainingParameters();
void checkMuscle(int);

#endif // SETNODESANDMUSCLES_H

