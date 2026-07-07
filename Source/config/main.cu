// To compile the simulation type the line below in the terminal.
// This is also done for you in the compile linux script.
// nvcc main.cu -o svt -lglut -lm -lGLU -lGL

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
#include "globals.h"
#include "file_io.h"
#include "callbacks.h"
#include "view.h"
#include "gui.h"
#include "utils.h"


/*
 Setting up the CUDA environment. We have three:
 1: Node based
 2: Muscle based
 3: Just one block used for re-centering the simulation.
*/





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
	// It is important that this is a positive number, as the camera looks down the negative z axis. 
	// If this is negative you will be looking at the back of the LA instead of the front. The front of the LA is what we are interested in so we want to be looking at that. 
	// We also want to be far enough away to see the whole thing, but not too far away or it will look small and we will lose detail. 
	// 75 seems to be a good number for this, but feel free to change it and see how it looks.
	// SPECIFICALLY: If this is negative, the mouse directions become inverted and the drawFrontHalf function breaks.
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
	GLfloat mat_shininess[]  = {128.0}; //how shiny is the surface of an object, 0.0 is dull, 128.0 is very shiny
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

	createSphereVBO(NodeRadiusAdjustment * RadiusOfLeftAtrium, 10, 10); //the first arg was the radius used in the draw nodes flag

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
		
		// Always draw every frame - this is critical for GLFW performance
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

	//shutdown ImGui
	ImGui_ImplOpenGL3_Shutdown();
	ImGui_ImplGlfw_Shutdown();
	ImGui::DestroyContext();

	//destroy the window and terminate GLFW
	glfwDestroyWindow(Window);
  	glfwTerminate();

	return 0;
}
