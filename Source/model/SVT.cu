// To compile the simulation type the line below in the terminal.
// This is also done for you in the compile linux script.
// nvcc SVT.cu -o svt -lglut -lm -lGLU -lGL

/*
 This file contains all the the main controller functions that setup the simulation, then run and manage the simulation.
 
 The functions are listed below in the order they appear.
 
 void nBody(double);
 void setupCudaEnvironment();
 void readSimulationParameters();
 void readBasicSimulationSetupParameters();
 void readIntermediateSimulationSetupParameters();
 void readAdvancedSimulationSetupParameters();
 void setup();
 int main(int, char**);
*/

// Local include files
#include "./header.h"
#include "./setNodesAndMuscles.h"
#include "./callBackFunctions.h"
#include "./viewDrawAndTerminalFunctions.h"
#include "./cudaFunctions.h"

/*
 This function is called by the openGL idle function. Hence this function is called every time openGL is not doing anything else,
 which is most of the time.
 This function orchestrates the simulation by;
 1: Calling the getForces function which gets all the forces except the drag force on all nodes.
 2: Calling the upDateNodes function which moves the nodes based off of the forces from the getForces function.
    It uses the leap-frog formulas to integrate the nodes forward in time. It also sees if a node is a beat node  
    and if it needs to send out a signal.
 3: Calling the updateMuscles function to adjust where they are in their cycle and react accordingly.
 4: Sees if it is time to recenter the simulation.
 5: Sees if simulation needs to be redrawn to the screen.
 6: Sees if the terminal screen needs to be updated.
 
 Note: If Pause is on it skips all this and if Contraction is not on it skips all of its moving calculations
 and only performs calculations that deal with electrical conduction and muscle timing. 
*/
void nBody(double dt)
{	
	//no need to check if we're paused because we handle that in main

	if(Simulation.ContractionisOn)
	{
		getForces<<<GridNodes, BlockNodes, 0, ComputeStream>>>(MuscleGPU, NodeGPU, dt, NumberOfNodes, CenterOfSimulation, MuscleCompressionStopFraction, RadiusOfLeftAtrium, DiastolicPressureLA, SystolicPressureLA);
		cudaErrorCheck(__FILE__, __LINE__);
	}

	updateNodes<<<GridNodes, BlockNodes, 0, ComputeStream>>>(NodeGPU, NumberOfNodes, MUSCLES_PER_NODE, MuscleGPU, Drag, dt, RunTime, Simulation.ContractionisOn);
	cudaErrorCheck(__FILE__, __LINE__);

	updateMuscles<<<GridMuscles, BlockMuscles, 0, ComputeStream>>>(MuscleGPU, NodeGPU, NumberOfMuscles, NumberOfNodes, dt, ReadyColor, DepolarizingColor, RepolarizingColor, RelativeRepolarizingColor);
	cudaErrorCheck(__FILE__, __LINE__);
	
	if(Simulation.ContractionisOn)
	{
		RecenterCount++;
		if(RecenterCount == RecenterRate) 
		{
			recenter<<<1, BLOCKCENTEROFMASS, 0, ComputeStream>>>(NodeGPU, NumberOfNodes, MassOfLeftAtrium, CenterOfSimulation);
			cudaErrorCheck(__FILE__, __LINE__);
			RecenterCount = 0;
		}
	}
	
	RunTime += dt;
}

/*
 Setting up the CUDA environment. We have three:
 1: Node based
 2: Muscle based
 3: Just one block used for re-centering the simulation.
*/
void setupCudaEnvironment()
{
	// 1:
	BlockNodes.x = BLOCKNODES;
	BlockNodes.y = 1;
	BlockNodes.z = 1;
	
	GridNodes.x = (NumberOfNodes - 1)/BlockNodes.x + 1;
	GridNodes.y = 1;
	GridNodes.z = 1;
	
	// 2:
	BlockMuscles.x = BLOCKMUSCLES;
	BlockMuscles.y = 1;
	BlockMuscles.z = 1;
	
	GridMuscles.x = (NumberOfMuscles - 1)/BlockMuscles.x + 1;
	GridMuscles.y = 1;
	GridMuscles.z = 1;
	
	// 3:
	if((BLOCKCENTEROFMASS > 0) && (BLOCKCENTEROFMASS & (BLOCKCENTEROFMASS - 1)) != 0) 
	{
		printf("\n\n BLOCKCENTEROFMASS = %d. This is not a power of 2.", BLOCKCENTEROFMASS);
		printf("\n BLOCKCENTEROFMASS must be a power of 2 for the center of mass reduction to work.");
		printf("\n Fix this number in the header.h file and try again.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
    }
}

/*
 This function reads in all the user defined parameters in the BasicSimulationSetup file.
*/
void readBasicSimulationSetupParameters()
{
	ifstream data;
	string name;
	
	data.open("./BasicSimulationSetup");
	if(data.is_open() == 1)
	{
		getline(data,name,'=');
		data >> NodesMusclesFileOrPreviousRunsFile;
		
		getline(data,name,'=');
		data >> NodesMusclesFileName;
		
		getline(data,name,'=');
		data >> PreviousRunFileName;
		
		getline(data,name,'=');
		data >> LineWidth;
		
		getline(data,name,'=');
		data >> NodeRadiusAdjustment;
		
		getline(data,name,'=');
		data >> NodePointSize;
		
		getline(data,name,'=');
		data >> Simulation.ContractionisOn;
		
		getline(data,name,'=');
		data >> BackGround.x;
		
		getline(data,name,'=');
		data >> BackGround.y;
		
		getline(data,name,'=');
		data >> BackGround.z;
	}
	else
	{
		printf("\n\n Could not open BasicSimulationSetup file.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	data.close();
	printf("\n Basic Simulation Parameters have been read in from BasicSimulationSetup file.\n");
}

/*
 This function reads in all the user defined parameters in the IntermediateSimulationSetup file.
*/
void readIntermediateSimulationSetupParameters()
{
	ifstream data;
	string name;
	
	data.open("./IntermediateSimulationSetup");
	if(data.is_open() == 1)
	{
		getline(data,name,'=');
		data >> BaseMuscleRefractoryPeriod;
		
		getline(data,name,'=');
		data >> MuscleRefractoryPeriodSTD;
		        
		getline(data,name,'=');
		data >> BaseAbsoluteRefractoryPeriodFraction;
		
		getline(data,name,'=');
		data >> AbsoluteRefractoryPeriodFractionSTD;
		
		getline(data,name,'=');
		data >> BaseMuscleConductionVelocity;
		
		getline(data,name,'=');
		data >> MuscleConductionVelocitySTD; 
		
		getline(data,name,'=');
		data >> BachmannsBundleMultiplier;
		
		getline(data,name,'=');
		data >> BeatPeriod;
		
		getline(data,name,'=');
		data >> PrintRate;
		
		getline(data,name,'=');
		data >> DrawRate;
		
		getline(data,name,'=');
		data >> Dt;
		
		getline(data,name,'=');
		data >> ReadyColor.x;
		
		getline(data,name,'=');
		data >> ReadyColor.y;
		
		getline(data,name,'=');
		data >> ReadyColor.z;
		
		getline(data,name,'=');
		data >> DepolarizingColor.x;
		
		getline(data,name,'=');
		data >> DepolarizingColor.y;
		
		getline(data,name,'=');
		data >> DepolarizingColor.z;
		
		getline(data,name,'=');
		data >> RepolarizingColor.x;
		
		getline(data,name,'=');
		data >> RepolarizingColor.y;
		
		getline(data,name,'=');
		data >> RepolarizingColor.z;
		
		getline(data,name,'=');
		data >> RelativeRepolarizingColor.x;
		
		getline(data,name,'=');
		data >> RelativeRepolarizingColor.y;
		
		getline(data,name,'=');
		data >> RelativeRepolarizingColor.z;
		
		getline(data,name,'=');
		data >> DeadColor.x;
		
		getline(data,name,'=');
		data >> DeadColor.y;
		
		getline(data,name,'=');
		data >> DeadColor.z;
		
		getline(data,name,'=');
		data >> BachmannColor.x;
		
		getline(data,name,'=');
		data >> BachmannColor.y;
		
		getline(data,name,'=');
		data >> BachmannColor.z;
	}
	else
	{
		printf("\n\n Could not open IntermediateSimulationSetup file.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	data.close();
	printf("\n Intermediate Simulation Parameters have been read in from IntermediateSimulationSetup file.\n");
}

/*
 This function reads in all the user defined parameters in the AdvancedSimulationSetup file.
*/
void readAdvancedSimulationSetupParameters()
{
	ifstream data;
	string name;
	
	data.open("./AdvancedSimulationSetup");
	if(data.is_open() == 1)
	{
		getline(data,name,'=');
		data >> WallThicknessFraction;
		
		getline(data,name,'=');
		data >> MyocyteLength;
		
		getline(data,name,'=');
		data >> MyocyteDiameter;
		
		getline(data,name,'=');
		data >> MyocyteContractionForce;
		
		getline(data,name,'=');
		data >> MyocardialTissueDensity;
		
		getline(data,name,'=');
		data >> MyocyteForcePerMassMultiplier;
		
		getline(data,name,'=');
		data >> MyocyteForcePerMassSTD;
		
		getline(data,name,'=');
		data >> DiastolicPressureLA;
		
		getline(data,name,'=');
		data >> SystolicPressureLA;
		
		getline(data,name,'=');
		data >> PressureMultiplier;
		
		getline(data,name,'=');
		data >> Drag;
		
		getline(data,name,'=');
		data >> MuscleRelaxedStrengthFraction;
		
		getline(data,name,'=');
		data >> MuscleCompressionStopFraction;
		
		getline(data,name,'=');
		data >> MuscleCompressionStopFractionSTD;
	}
	else
	{
		printf("\n\n Could not open AdvancedSimulationSetup file.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	data.close();
	
	// Adjusting blood pressure from millimeters of Mercury to our units.
	// We simulate blood pressure as a central push-back force.
	// 1 millimeter of mercury is 133.322387415 Pascals or kg/(meters*seconds*seconds).
	// Converting this into our units of grams, milliseconds, and millimeters gives 0.000133322387415.
	// Therefore, 1 millimeter of mercury is equivalent to 0.000133322387415 in our units of g/(mm*ms*ms).
	DiastolicPressureLA *= 0.000133322387415*PressureMultiplier; 
	SystolicPressureLA  *= 0.000133322387415*PressureMultiplier;
	
	printf("\n Advanced Simulation Parameters have been read in from AdvancedSimulationSetup file.\n");
}

/*
 This function calls all the functions that are used to setup the nodes muscles and initial parameters 
 of the simulation.
*/
void setup()
{	

	// Seeding the random number generator.
	time_t t;
	srand((unsigned) time(&t));

	//create CUDA streams for async memory copy and compute
	cudaStreamCreate(&ComputeStream);
	cudaStreamCreate(&MemoryStream);
		
	// Getting user inputs.
	readBasicSimulationSetupParameters();
	readIntermediateSimulationSetupParameters();
	readAdvancedSimulationSetupParameters();
	
	// Getting nodes and muscle from files or a previous run file.
	if(NodesMusclesFileOrPreviousRunsFile == 0)
	{
		readNodesAndMusclesFromBinaryFile();

		/*
		readNodesFromFile();
		centerNodes();
		checkNodes();
		readPulseUpAndFrontNodesFromFile();
		readBachmannBundleFromFile();
		readAndConnectMusclesFromFile();
		linkNodesToMuscles();
		*/

		findRadiusAndMassOfLeftAtrium();
		setRemainingNodeAndMuscleAttributes();
		for(int i = 0; i < NumberOfMuscles; i++)
		{	
			checkMuscle(i);
		}
	}
	else if(NodesMusclesFileOrPreviousRunsFile == 1)
	{
		getNodesandMusclesFromPreviousRun();
	}
	else
	{
		printf("\n\n Bad NodesMusclesFileOrPreviousRunsFile type %d.", NodesMusclesFileOrPreviousRunsFile);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	// Setting parameters that are not initially read from the node and muscle or previous run file.
	setRemainingParameters();
	
	// Setting up the CUDA parallel structure to be used.
	setupCudaEnvironment();

	// Sending all the info that we have just created to the GPU so it can start crunching numbers.
	copyNodesMusclesToGPU();
	
	printf("\n\n Have a good simulation.\n\n");
}

/*
 In main we mostly just setup the openGL environment and kickoff the glutMainLoop function.
*/
int main(int argc, char** argv)
{
	setup();
	
	XWindowSize = 1800; //1800
	YWindowSize = 1000; //1000

	// Clip plains
	Near = 0.2;
	Far = 80.0*RadiusOfLeftAtrium;

	//Where your eye is located
	EyeX = 0.0*RadiusOfLeftAtrium;
	EyeY = 0.0*RadiusOfLeftAtrium;
	EyeZ = 2.0*RadiusOfLeftAtrium;

	//Where you are looking
	CenterX = 0.0;
	CenterY = 0.0;
	CenterZ = 0.0;

	//Up vector for viewing
	UpX = 0.0;
	UpY = 1.0;
	UpZ = 0.0;

    if(!glfwInit()) // Initialize GLFW, check for failure
    {
        fprintf(stderr, "Failed to initialize GLFW\n");
        return -1;
    }

	// Set compatibility mode to allow legacy OpenGL (this is just standard)
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2); //these 2 lines are for compatibility with older versions of OpenGL (2.1+) ensures backwards compatibility
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_ANY_PROFILE); //this line is for compatibility with older versions of OpenGL

	// Create a windowed mode window and its OpenGL context
	Window = glfwCreateWindow(XWindowSize, YWindowSize, "SVT", NULL, NULL); // args: width, height, title, monitor, share
	if (!Window) 
	{
		fprintf(stderr, "Failed to create window\n");
		return -1;
	}

	// Make the window's context current
    glfwMakeContextCurrent(Window); // Make the window's context current, meaning that all future OpenGL commands will apply to this window
    glfwSwapInterval(1); // Enable vsync (1 = on, 0 = off), vsync is a method used to prevent screen tearing which occurs when the GPU is rendering frames at a rate faster than the monitor can display them

	if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress))  // Initialize GLAD, check for failure
	{
		fprintf(stderr, "Failed to initialize GLAD\n");
		glfwTerminate();
		return -1;
	}

	glfwSetInputMode(Window, GLFW_STICKY_KEYS, GLFW_TRUE);
	glfwSetInputMode(Window, GLFW_REPEAT, GLFW_TRUE);  // Explicitly enable key repeat

	//create a sphere VBO for drawing the nodes (since allnodes are the same we create one VBO and use it for all nodes)
	createSphereVBO(NodeRadiusAdjustment * RadiusOfLeftAtrium, 20, 20); //the first arg was the radius used in the draw nodes flag

	//these set up our callbacks, most have been changed to adapters until GUI is implemented
	glfwSetFramebufferSizeCallback(Window, reshape);  //sets the callback for the window resizing
	glfwSetCursorPosCallback(Window, mousePassiveMotionCallback); //sets the callback for the cursor position
	glfwSetMouseButtonCallback(Window, myMouse); //sets the callback for the mouse clicks
	glfwSetScrollCallback(Window, scrollWheel); //sets the callback for the mouse wheel
	glfwSetKeyCallback(Window, KeyPressed); //sets the callback for the keyboard
	
	// Set the clear color to the background color
	glClearColor(BackGround.x, BackGround.y, BackGround.z, 1.0f);

	//Lighting and material properties
	glEnable(GL_LIGHTING);
	glEnable(GL_LIGHT0);
	//GLfloat light_position[] = {EyeX, EyeY, EyeZ, 0.0};
	GLfloat light_position[] = {1.0, 1.0, 1.0, 0.0}; //where the light is: {x,y,z,w}, w=0.0 is infinite light aiming at x,y,z, w=1.0 is a point light radiating from x,y,z
	GLfloat light_ambient[]  = {0.35, 0.35, 0.35, 1.0}; //what color is the ambient light, {r,g,b,a}, a= opacity 1.0 is fully visible, 0.0 is invisible
	GLfloat light_diffuse[]  = {0.35, 0.35, 0.35, 1.0}; //does light reflect off of the object, {r,g,b,a}, a has no effect
	GLfloat light_specular[] = {1.0, 1.0, 1.0, 1.0}; //does light highlight shiny surfaces, {r,g,b,a}. i.e what light reflects to viewer
	GLfloat lmodel_ambient[] = {0.5, 0.5, 0.5, 1.0}; //global ambient light, {r,g,b,a}, applies uniformly to all objects in the scene
	GLfloat mat_specular[]   = {1.0, 1.0, 1.0, 1.0}; //reflective properties of an object, {r,g,b,a}, highlights are currently white
	GLfloat mat_shininess[]  = {64.0}; //how shiny is the surface of an object, 0.0 is dull, 128.0 is very shiny
	glShadeModel(GL_SMOOTH);
	glColorMaterial(GL_FRONT, GL_AMBIENT_AND_DIFFUSE);
	glLightfv(GL_LIGHT0, GL_POSITION, light_position);
	glLightfv(GL_LIGHT0, GL_AMBIENT, light_ambient);
	glLightfv(GL_LIGHT0, GL_DIFFUSE, light_diffuse);
	glLightfv(GL_LIGHT0, GL_SPECULAR, light_specular);
	glLightModelfv(GL_LIGHT_MODEL_AMBIENT, lmodel_ambient);
	glMaterialfv(GL_FRONT, GL_SPECULAR, mat_specular);
	glMaterialfv(GL_FRONT, GL_SHININESS, mat_shininess);

	glEnable(GL_COLOR_MATERIAL);
	glEnable(GL_DEPTH_TEST);

	//*****************************************Set up GUI********************************
	// Initialize ImGui
	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO(); (void)io;
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;  // Enable keyboard controls

	// Setup ImGui style
	ImGui::StyleColorsDark();  // Choose a style (Light, Dark, or Classic)
	ImGuiStyle& style = ImGui::GetStyle(); // Get the current style
	style.Colors[ImGuiCol_WindowBg].w = 1.0f;  // Set window background color

	// Setup Platform/Renderer backends
	ImGui_ImplGlfw_InitForOpenGL(Window, true);  //connect ImGui to GLFW
	ImGui::GetIO().ConfigFlags |= ImGuiConfigFlags_NavNoCaptureKeyboard; //prevent ImGui from capturing keyboard input, allowing GLFW to handle it instead
	ImGui_ImplOpenGL3_Init("#version 130");      //Chooses OpenGL version 3.0, this is the version that is compatible with the current version of ImGui

	// Load a font
	io.Fonts->AddFontDefault();

	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);


	//*****************************************End GUI Setup********************************

	//Initialize the window with aspect ratio and projection matrix

	/*
		NOTE: 

		the reshape function which calculated the aspect ratio and projection matrix to allow us to resize without changing the aspect ratio
		caused the simulation to not display properly when the window was first created and would stay that way until the window was resized.

		and calling resize didn't work, so I basically copied everything here and got the window size instead of XWindowSize and YWindowSize
		because X and Y windows size don't work for this

	*/
	// Get current size
    int width, height;
    glfwGetFramebufferSize(Window, &width, &height);
    
	// Update stored window size and set initial render size
	XWindowSize = width;
	YWindowSize = height;
	// Initialize capture size to the current window size so screenshots work before any capture starts
	CaptureWidth = XWindowSize;
	CaptureHeight = YWindowSize;

	// Reset viewport and matrices to ensure proper initial state
	glViewport(0, 0, XWindowSize, YWindowSize);
    
	// Reset projection matrix
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();

	// Calculate aspect ratio using the render size
	float aspect = (float)XWindowSize / (float)YWindowSize;

	// Set projection based on the view flag
	if(Simulation.ViewFlag == 0) // Orthogonal view
	{
		glOrtho(-aspect, aspect, -1.0, 1.0, -1.0, 1.0); // Orthographic projection
	}
	else // Frustum view
	{
		glFrustum(-aspect, aspect, -1.0, 1.0, 1.0, 100.0); // Perspective projection
	}
    
    // Reset modelview matrix
	// MODELVIEW MATRIX - this controls camera position
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity(); //Necessary here
    gluLookAt(EyeX, EyeY, EyeZ, CenterX, CenterY, CenterZ, UpX, UpY, UpZ);
    
    // Draw once to initialize everything
    drawPicture();
    glfwSwapBuffers(Window);
	
	// Main loop
	while (!glfwWindowShouldClose(Window))
	{
		glfwPollEvents();

		keyHeld(Window); // Handle key hold events

		// Start ImGui frame
		ImGui_ImplOpenGL3_NewFrame();
		ImGui_ImplGlfw_NewFrame();

		ImGui::NewFrame();
		
		// Update physics --multiple steps per frame for performance
		if (!Simulation.isPaused) 
		{
			// Execute nBody DrawRate times before we draw
			for (int i = 0; i < DrawRate; i++) 
			{
				//if(RunTime < 25.0) nBody(Dt/10.0); // Ease into the simulation.
				//else nBody(Dt);
				nBody(Dt);
				// Check if we hit the 10ms mark and need to pause
				if (Simulation.isPaused) 
				{
					break;  // Exit the loop if simulation gets paused
				}
			}
		}
		
		// Always draw every frame - this is critical for GLFW performance
		cudaStreamSynchronize(ComputeStream); 
		copyNodesMusclesFromGPU();
		drawPicture();
		
		// Create and render GUI
		createGUI();
		ImGui::Render();
		ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
		
		// Swap buffers
		glfwSwapBuffers(Window);
	}
		
	//Destroy streams
	cudaStreamDestroy(ComputeStream);
  	cudaStreamDestroy(MemoryStream);

	//delete the state file if it exists
	remove("simulation_state.bin");

	//free memory
	cudaFreeHost(Node);
	cudaFreeHost(Muscle);
	cudaFree(NodeGPU);
	cudaFree(MuscleGPU);

	//shutdown ImGui
	ImGui_ImplOpenGL3_Shutdown();
	ImGui_ImplGlfw_Shutdown();
	ImGui::DestroyContext();

	//destroy the window and terminate GLFW
	glfwDestroyWindow(Window);
  	glfwTerminate();

	return 0;
}
