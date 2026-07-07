/*
 This file contains all include files, the #defines, structures and globals used in the simulation.
 All the functions are prototyped in this file as well.
*/

#ifndef HEADER_H
#define HEADER_H

// External include files
#include <iostream>
#include <fstream>
#include <sstream>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>
#include <stdbool.h>
#include <vector> //needed for VBOs

// Needed to make 
#include <cuda_runtime.h>

// OpenGL headers - GLAD must come BEFORE GLFW
#include "../include/glad/glad.h"
#include <GL/glu.h>
#include <GLFW/glfw3.h>

// ImGui headers - use quotes for local includes, not angle brackets
#include "../third_party/imgui/imgui.h"
#include "../third_party/imgui/imgui_impl_glfw.h"
#include "../third_party/imgui/imgui_impl_opengl3.h"


// TODO absolutely need to remove this, it can mess up a lot of code
using namespace std;

// Cuda defines
#define BLOCKNODES 256
#define BLOCKMUSCLES 256
#define BLOCKCENTEROFMASS 512
#define FLOATMAX 3.4028235e+38f
#define INTMAX 2147483647

// Defines for terminal print
#define BOLD_ON  "\e[1m"
#define BOLD_OFF   "\e[m"

// Math defines.
#define PI 3.141592654
#define ASUMEZERO 0.0000001f

// Structure defines. 
// This sets how many muscle can be connected to a node.
#define MUSCLES_PER_NODE 20

//Node types
const int NODE_TYPE_STANDARD = 0;
const int NODE_TYPE_BACHMANN_BUNDLE = 1;
const int NODE_TYPE_APPENDAGE = 2;
const int NODE_TYPE_SCAR_TISSUE = 3; // This is not implemented yet but will be used to make scar tissue in the future.
const int NODE_TYPE_PULMONARY_VEINS = 4;
const int NODE_TYPE_MITRAL_VALVE = 5;

// Mouse modes, which will use the same int values as the node types for simplicity, but with -1 for off mode.
const int MOUSE_MODE_OFF = -1;
const int MOUSE_MODE_STANDARD = NODE_TYPE_STANDARD;
const int MOUSE_MODE_BACHMANNS_BUNDLE = NODE_TYPE_BACHMANN_BUNDLE;
const int MOUSE_MODE_APPENDAGE = NODE_TYPE_APPENDAGE;
const int MOUSE_MODE_SCAR_TISSUE = NODE_TYPE_SCAR_TISSUE; // This is not implemented yet but will be used to make scar tissue in the future.
const int MOUSE_MODE_PULMONARY_VEINS = NODE_TYPE_PULMONARY_VEINS;
const int MOUSE_MODE_MITRAL_VALVE = NODE_TYPE_MITRAL_VALVE;
const int MOUSE_MODE_PULSE_NODE = 100;
const int MOUSE_MODE_BACK_TOP = 101;


const float4 COLOR_STANDARD = {1.0f, 0.0f, 0.0f, 0.0f}; // Mostly white for standard nodes (to reduce contrast)
const float4 COLOR_BACHMANNS_BUNDLE= {0.2f, 0.2f, 1.0f, 0.0f}; // Blue for Bachmann's Bundle nodes and muscles by default.
const float4 COLOR_APPENDAGE = {0.0f, 0.7f, 0.0f, 0.0f}; // Green for left atrial appendage nodes and muscles by default.
const float4 COLOR_SCAR_TISSUE = {0.6f, 0.6f, 0.6f, 0.0f}; // Gray for scar tissue nodes and muscles by default.
const float4 COLOR_PULMONARY_VEINS = {1.0f, 0.5f, 0.0f, 0.0f}; // Orange for pulmonary veins nodes and muscles by default.
const float4 COLOR_MITRAL_VALVE = {1.0f, 0.0f, 1.0f, 0.0f}; // Magenta for mitral valve nodes and muscles by default.

// Simulation mode defines. I am fairly sure these will not be needed but will be useful for the main program.
const int SIM_MODE_STANDARD = 0;
const int SIM_MODE_MUSCLE_LINE_SELECT = 1;
const int SIM_MODE_NODE_ADJUST = 2; // Ideally this would be any mode where you are selecting nodes to adjust attributes, and then the mouse mode can narrow it down further.

// Structures
// Everything a node holds. We have 1 on the CPU and 1 on the GPU
typedef struct 
{
	float4 position;
	float4 color;
	int type;
	int muscle[MUSCLES_PER_NODE];
	float mass = 0.005266; // We took the average mass per node from the original program. Mass is only used to calculate COM for rotations in this program so any number should work here.
} nodeAttributesStructure;

// Everything a muscle holds. We have 1 on the CPU and 1 on the GPU
typedef struct 
{
	int type;
	int nodeA;
	int nodeB;    
	float4 color;
} muscleAttributesStructure; 

// This structure will contain all the switches that control the actions in the code.
// 
typedef struct 
{
	int mouseMode; // can be used to set the mode of the mouse, like ablate mode, ectopic beat mode, adjust muscle area mode, or adjust muscle line mode.
	int ViewFlag; 
	int DrawNodesFlag; 
	int DrawFrontHalfFlag;
	bool ShowMuscleTypesFlag;
	bool isInMouseFunctionMode; // This is true if the user is in any of the mouse function modes, like ablate mode, ectopic beat mode, adjust muscle area mode, or adjust muscle line mode.
	bool guiCollapsed; // for hotkey to collapse GUI
} simulationSwitchesStructure;

// Globals Start ******************************************
// Make sure any globals that are not initialived in one of the simulation setup files
// (AdvancedSimulationSetup, IntermediateSimulationSetup, BasicSimulationSetup) are save
// when a simulation is saved in the previuos runs file.

// How many nodes and muscle the simulation contains.
// They are initially read in form files in the NodesMuscles folder.
// *** Should be stored if a runfile is saved.
int NumberOfNodes;
int NumberOfMuscles;
int NumberOfNodesInBachmannsBundle;
int NumberOfNodesInLeftAtrialAppendage;
// This will hold all the nodes.
// It is initially read in form files in the NodesMuscles folder.
// *** The Nodes (CPU values) should be stored if a runfile is saved.
nodeAttributesStructure *Node;

// This will hold all the muscles.
// It is initially read in form files in the NodesMuscles folder.
// *** The Muscles (CPU values) should be stored if a runfile is saved.
muscleAttributesStructure *Muscle;

// This will hold all the nodes that extend from the beat node to create Bachmann's Bundle.
// It is initially read in form files in the NodesMuscles folder.
// *** This should be stored if a runfile is saved.
int *BachmannsBundle;
int *LeftAtrialAppendage;

// This will hold all the simulation switches.
// It is initialized in setNodesAndMuscles.h/setRemainingParameters().
// *** Should be stored if a runfile is saved.
simulationSwitchesStructure Simulation;

// Used for videos and screenshots variables
// CaptureWidth and CaptureHeight they are intially in Main().
// MovieFile and Buffer are opened/allocated in callBackFunctions.h/movieOn()
// and closed/freed in callBackFunctions.h/movieOff().
FILE* MovieFile; // File that holds all the movie frames.
unsigned char* Buffer; // Buffer where you create each frame for a movie or the one frame for a screen shot.
int CaptureWidth, CaptureHeight; // Locked capture size (set when capture starts)

// Used to setup your CUDA device
// These are initialized in SVT.cu/setupCudaEnvironment().
dim3 BlockNodes, GridNodes;
dim3 BlockMuscles, GridMuscles;

// CUDA streams for overlapping memory and kernel operations.
// They are created in SVT.cu/setup(), and destroyed in SVT.cu/Main().
cudaStream_t ComputeStream, MemoryStream;

// To use VBOs for sphere rendering
GLuint SphereVBO, SphereIBO; // Vertex Buffer Object and Index Buffer Object for sphere rendering, Vertex is the sphere's vertices and Index is the order in which to draw them.
GLuint NumSphereVertices, NumSphereIndices; // Number of vertices and indices in the sphere geometry

// This is the node that the beat initiates from.
// It is initially read in form files in the NodesMuscles folder.
// *** Should be stored if a runfile is saved.
int PulsePointNode = -1; // Set to -1 to flag it if it is used before it is set.

// Nodes that orient the simulation. 
// If the node's center of mass is at <0,0,0> and the UpNode is up and FrontNode is in the front looking at you, you should be in the standard view.
// They are initially read in form files in the NodesMuscles folder.
// *** Should be stored if a runfile is saved.
int UpNode = -1; // Set to -1 to flag it if it is used before it is set.
int FrontNode = -1; // Set to -1 to flag it if it is used before it is set.

// Holds the name of the medical view you are in for displaying in the terminal print.
// It is initialized here.
// *** Should be stored if a runfile is saved.
char ViewName[256] = "no view set"; 

// Status line shown in GUI after saving binary files.
char BinarySaveStatusMessage[512] = "";

// These two variable get user input to adjust muscle refractory periods and conduction velocities when you are
// in AdjustMuscleAreaMode or AdjustMuscleLineMode modes. Once they are read in, they are multiplied by the muscles 
// refractory period and conduction velocity respectively. 
// They are initialized in setNodesAndMuscles.h/setRemainingParameters().
// *** Should be stored if a runfile is saved.
float RefractoryPeriodAdjustmentMultiplier = -1.0; // Set to -1.0 to flag it if it is used before it is set.
float MuscleConductionVelocityAdjustmentMultiplier = -1.0; // Set to -1.0 to flag it if it is used before it is set.

// These are all the globals that are read in from the BasicSimulationSetup file and are explained in detail there.
int NodesMusclesFileOrPreviousRunsFile;
char NodesMusclesFileName[256];
char PreviousRunFileName[256];
float LineWidth;
float NodeRadiusAdjustment;
float NodePointSize;
// Simulation.ContractionisOn -- Value initialized here but this global is defined above.
float4 BackGround;

// These are all the globals that are read in from the IntermediateSimulationSetup file and are explained in detail there.
double BaseMuscleRefractoryPeriod;
double MuscleRefractoryPeriodSTD;
double BaseAbsoluteRefractoryPeriodFraction;
double AbsoluteRefractoryPeriodFractionSTD;
double BaseMuscleConductionVelocity;
double MuscleConductionVelocitySTD;
double BachmannsBundleMultiplier;
double BeatPeriod;
double PrintRate;
int DrawRate;
double Dt;
float4 ReadyColor;
float4 DepolarizingColor;
float4 RepolarizingColor;
float4 RelativeRepolarizingColor;
float4 DeadColor;
float4 BachmannColor;

// These are all the globals that are read in from the AdvancedSimulationSetup file and are explained in detail there.
double WallThicknessFraction;		
double MyocyteLength; 
double MyocyteDiameter;
double MyocyteContractionForce;
double MyocardialTissueDensity;
double MyocyteForcePerMassMultiplier;
double MyocyteForcePerMassSTD;
double DiastolicPressureLA;
double SystolicPressureLA;
double PressureMultiplier;
double Drag;
double MuscleRelaxedStrengthFraction;
double MuscleCompressionStopFraction;
double MuscleCompressionStopFractionSTD;

// This will hold the radius of the left atrium which we will use to scale the size of everything in the simulation.
// It is calculated in setNodesAndMuscles.h/findRadiusAndMassOfLeftAtrium().
// *** Should be stored if a runfile is saved.
double RadiusOfLeftAtrium = -1.0; // Set to -1.0 to flag it if it is used before it is set.

// This will hold the mass of the left atrium.
// It is calculated in setNodesAndMuscles.h/findRadiusAndMassOfLeftAtrium().
// *** Should be stored if a runfile is saved.
double MassOfLeftAtrium = -1.0; // Set to -1.0 to flag it if it is used before it is set.

// This will hold the force per mass fraction of a myocte which we will use to scale a a muscles strength
// by its mass.
// It is calculated in setNodesAndMuscles.h/setRemainingNodeAndMuscleAttributes().
// *** Should be stored if a runfile is saved.
double MyocyteForcePerMassFraction = -1.0; // Set to -1.0 to flag it if it is used before it is set.

// Variable that holds mouse locations to be translated into positions in the simulation and mouse other functionality.
// They are initialized in setNodesAndMuscles.h/setRemainingParameters().
// TODO: Convert these to a float3 or double3
double MouseX, MouseY, MouseZ;
int MouseWheelPos;
float HitMultiplier; // Adjusts how big of a region the mouse covers when you are selecting with it.
int ScrollSpeedToggle; // Sets slow or fast scroll speed.
double ScrollSpeed; // How fast your scroll moves.

// These set how often you recenter the nodes. The nodes will drift off because of roundoff and other things
// and need to be recentered periodically.
// They are initialized in setNodesAndMuscles.h/setRemainingParameters().
int RecenterCount = -1; // Set to -1 to flag it if it is used before it is set.
int RecenterRate = -1; // Set to -1 to flag it if it is used before it is set.

// Keeps track of the time into the simulation.
// It is initialized in setNodesAndMuscles.h/setRemainingParameters().
// *** Should be stored if a runfile is saved.
double RunTime = -1.0; // Set to -1.0 to flag it if it is used before it is set.

// These keep track of where the view is as you zoom in and out and rotate.
// These are initialized in setNodesAndMuscles.h/setRemainingParameters().
// *** Should be stored if a runfile is saved.
float4 CenterOfSimulation;
float4 AngleOfSimulation;

// Window globals 
// They are all initialized in main().
GLFWwindow* Window; // Window pointer
int XWindowSize;
int YWindowSize; 
double Near; // Front and back of clip planes
double Far;
double EyeX; // Where your eye is
double EyeY;
double EyeZ;
double CenterX; // Where you are looking
double CenterY;
double CenterZ;
double UpX; // What up means to the viewer
double UpY;
double UpZ;
	
// Prototyping functions start *****************************************************
// Functions in the SVT.h file.
void nBody(double);
void allocateMemory();
void readBasicSimulationSetupParameters();
void readIntermediateSimulationSetupParameters();
void readAdvancedSimulationSetupParameters();
void setup();
int main(int, char**);



// Functions in the setNodesAndMuscles.h file.
void setNodesFromBlenderFile();
void checkNodes();
void setBachmannBundleFromBlenderFile();
void setMusclesFromBlenderFile();
void linkNodesToMuscles();
bool setMuscleTypeAndColor(int muscleId);
bool setMuscleTypes();
double croppedRandomNumber(double, double, double);
void findRadiusAndMassOfLeftAtrium();
void setRemainingNodeAndMuscleAttributes();
void getNodesandMusclesFromPreviuosRun();
void setRemainingParameters();
void hardCodedAblations();
void hardCodedPeriodicEctopicEvents();
void hardCodedIndividualMuscleAttributes();
void checkMuscle(int);
 
// Functions in the viewDrawAndTerminalFunctions.h file.
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

// Functions in the callBackFunctions.h file.
void reshape(GLFWwindow* window, int width, int height);
void toggleNodeSelector(simulationSwitchesStructure* sim, int mode);
void setMouseMode(simulationSwitchesStructure* sim, int mode);
float4 getColorFromType(int type);
int setNodeMode(nodeAttributesStructure* node, int nodeType);
int checkIfNodeIsSelected(nodeAttributesStructure* node, float3 mousePos);
int assignNodes(nodeAttributesStructure* nodes, int length, float3 mousePos, int nodeType);
void mouseFunctionsOff();
void mouseAblateMode();
void mouseEctopicBeatMode();
void mouseAdjustMusclesAreaMode();
void mouseAdjustMusclesLineMode();
void mouseIdentifyNodeMode();
bool setMouseMuscleAttributes();
void setEctopicBeat(int nodeId);
void setPulseNode(int nodeId);
void setBackAndTopNodes(int backNodeId);
int findClosestNodeToMouse(float3 mousePos);
void clearStdin();
string getTimeStamp();
void saveBinary();
void movieOn();
void movieOff();
void screenShot();
void saveSettings();
void saveState();
void loadState();
void findNodes();
void KeyPressed(GLFWwindow* window, int key, int scancode, int action, int mods);
void keyHeld(GLFWwindow* window);
void mousePassiveMotionCallback(GLFWwindow* window, double x, double y);
void myMouse(GLFWwindow* window, int button, int state, double x, double y);
void scrollWheel(GLFWwindow*, double, double);

#endif // HEADER_H
