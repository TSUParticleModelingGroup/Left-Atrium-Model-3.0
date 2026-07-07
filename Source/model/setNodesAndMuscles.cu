/*
 This file contains all the functions that read in the nodes and muscles, links them together, 
 sets up the node and muscle attributes, and assigns them their values in our units. 
 Additionally it sets any remaining run parameters to get started in the setRemainingParameters() 
 function.
 
 The functions are listed below in the order they appear.
 
 void readNodesFromFile();
 void centerNodes();
 void checkNodes();
 void readPulseUpAndFrontNodesFromFile();
 void readBachmannBundleFromFile();
 void readAndConnectMusclesFromFile();
 void linkNodesToMuscles();
 double croppedRandomNumber(double, double, double);
 void findRadiusAndMassOfLeftAtrium();
 void setRemainingNodeAndMuscleAttributes();
 void getNodesandMusclesFromPreviousRun();
 void setRemainingParameters();
 void checkMuscle(int);
*/

#include "setNodesAndMuscles.h"

		
/*
 This function 
 1. Opens the node file.
 2. Finds the number of nodes.
 3. Allocates memory to hold the nodes on the CPU and the GPU
 4. Sets all the nodes to their default or start values.
 5. Reads and assigns the node positions from the node file.
 8. Sets the pulse node.
*/
void readNodesFromFile()
{	
	FILE *inFile;
	float x, y, z;
	int id;
	char fileName[256];
	
	// Generating the name of the file that holds the nodes.
	char directory[] = "./NodesMuscles/";
	strcpy(fileName, "");
	strcat(fileName, directory);
	strcat(fileName, NodesMusclesFileName);
	strcat(fileName, "/Nodes");
	
	// 1. Opening the node file.
	inFile = fopen(fileName,"rb");
	if(inFile == NULL)
	{
		printf("\n\n Can't open Nodes file %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	// 2. Reading the header information.
	fscanf(inFile, "%d", &NumberOfNodes);
	printf("\n NumberOfNodes = %d", NumberOfNodes);
	
	// 3. Allocating memory for the CPU and GPU nodes. 
	cudaHostAlloc((void**)&Node, NumberOfNodes*sizeof(nodeAttributesStructure), cudaHostAllocDefault); // Making page locked memory on the CPU.
	cudaErrorCheck(__FILE__, __LINE__);
	
	cudaMalloc((void**)&NodeGPU, NumberOfNodes*sizeof(nodeAttributesStructure));
	cudaErrorCheck(__FILE__, __LINE__);
	
	// 4. Setting all nodes to zero or their default settings; 
	for(int i = 0; i < NumberOfNodes; i++)
	{
		Node[i].position.x = 0.0;
		Node[i].position.y = 0.0;
		Node[i].position.z = 0.0;
		Node[i].position.w = 0.0;
		
		Node[i].velocity.x = 0.0;
		Node[i].velocity.y = 0.0;
		Node[i].velocity.z = 0.0;
		Node[i].velocity.w = 0.0;
		
		Node[i].force.x = 0.0;
		Node[i].force.y = 0.0;
		Node[i].force.z = 0.0;
		Node[i].force.w = 0.0;
		
		Node[i].mass = 0.0;
		Node[i].area = 0.0;
		
		Node[i].isBeatNode = false; // Setting all nodes to start out as not being a beat node.
		Node[i].beatPeriod = -1.0; // Setting bogus number so it will throw a flag later if something happens later on.
		Node[i].beatTimer = -1.0; // Setting bogus number so it will throw a flag later if something happens later on.
		Node[i].isFiring = false; // Setting the node fire button to false so it will not fire as soon as it is turned on.
		Node[i].isAblated = false; // Setting all nodes to not ablated.
		Node[i].isDrawNode = false; // This flag will allow you to draw certain nodes even when the draw nodes flag is set to off. Set it to off to start with.
		
		// Setting all node colors to not ablated (green)
		Node[i].color.x = 0.0;
		Node[i].color.y = 1.0;
		Node[i].color.z = 0.0;
		Node[i].color.w = 0.0;
		
		for(int j = 0; j < MUSCLES_PER_NODE; j++)
		{
			Node[i].muscle[j] = -1; // -1 sets the muscle to not used.
		}
	}
	
	// 5. Reading in the nodes positions.
	for(int i = 0; i < NumberOfNodes; i++)
	{
		fscanf(inFile, "%d %f %f %f", &id, &x, &y, &z);
		
		Node[id].position.x = x;
		Node[id].position.y = y;
		Node[id].position.z = z;
	}
	
	fclose(inFile);
	printf("\n Nodes positions have been read in.\n");
}

/*
 This function 
 1. Finds the center of the LA
 2. Places the center of the LA at (0,0,0).
*/
void centerNodes()
{
        // 1. Finding center on LA
	float4 centerOfObject;
	centerOfObject.x = 0.0;
	centerOfObject.y = 0.0;
	centerOfObject.z = 0.0;
	centerOfObject.w = (double)NumberOfNodes;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		 centerOfObject.x += Node[i].position.x;
		 centerOfObject.y += Node[i].position.y;
		 centerOfObject.z += Node[i].position.z;
	}
	centerOfObject.x /= centerOfObject.w;
	centerOfObject.y /= centerOfObject.w;
	centerOfObject.z /= centerOfObject.w;
	
	// 2. Centering the LA at (0,0,0)
	for(int i = 0; i < NumberOfNodes; i++)
	{
		Node[i].position.x -= centerOfObject.x;
		Node[i].position.y -= centerOfObject.y;
		Node[i].position.z -= centerOfObject.z;
	}
	printf("\n Nodes have been centered.\n");
}

/* This function checks to see if two nodes are too close relative to all the other nodes 
   in the simulations. 
   1: This for loop finds all the closest neighbor distances and then it calculates the average of this value. 
      This get a sense of how close nodes are in general. If you have more nodes they are going to be 
      closer together, this number just gets you a scale to compare to.
   2: This for loop checks to see if two nodes are closer than a cutoffDivider times smaller than the 
      average minimal distance. If it is, the nodes are printed out with their separation and a flag is set.
      Adjust the cutoffDivider for tighter and looser tolerances.
   3: If the flag is set, the simulation is terminated so the user can correct the node file that contains the faulty nodes.
*/
void checkNodes()
{
	float dx, dy, dz, d;
	float averageMinSeparation, minSeparation;
	bool flag;
	float cutoffDivider = 100.0;
	float cutoff;
	
	// 1: Finding average closest neighbor distance.
	averageMinSeparation = 0;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		minSeparation = FLOATMAX; // Setting min as a huge value just to get it started.
		for(int j = 0; j < NumberOfNodes; j++)
		{
			if(i != j)
			{
				dx = Node[i].position.x - Node[j].position.x;
				dy = Node[i].position.y - Node[j].position.y;
				dz = Node[i].position.z - Node[j].position.z;
				d = sqrt(dx*dx + dy*dy + dz*dz);
				if(d < minSeparation) 
				{
					minSeparation = d;
				}
			}
		}
		averageMinSeparation += minSeparation;
	}
	averageMinSeparation = averageMinSeparation/NumberOfNodes;
	
	// 2: Checking to see if nodes are too close together.
	cutoff = averageMinSeparation/cutoffDivider;
	flag = false;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		for(int j = 0; j < NumberOfNodes; j++)
		{
			if(i != j)
			{
				dx = Node[i].position.x - Node[j].position.x;
				dy = Node[i].position.y - Node[j].position.y;
				dz = Node[i].position.z - Node[j].position.z;
				d = sqrt(dx*dx + dy*dy + dz*dz);
				if(d < cutoff)
				{
					printf("\n Nodes %d and %d are too close. Their separation is %f", i, j, d);
					flag = true;
				}
			}
		}
	}
	
	// 3: Terminating the simulation if nodes were flagged and this switch is on.
	if(flag == true)
	{
		printf("\n\n The average nearest separation for all the nodes is %f.", averageMinSeparation);
		printf("\n The cutoff separation was %f.", cutoff);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	printf("\n Nodes have been checked for minimal separation.\n");
}

/*
 This function 
 1. Opens the PulseNodeUpNodeFrontNode file.
 2. Then reads in and sets the globals: PulsePointNode, UpNode, and FrontNode.
*/
void readPulseUpAndFrontNodesFromFile()
{	
	FILE *inFile;
	char fileName[256];
	
	// Generating the name of the file that holds the nodes.
	char directory[] = "./NodesMuscles/";
	strcpy(fileName, "");
	strcat(fileName, directory);
	strcat(fileName, NodesMusclesFileName);
	strcat(fileName, "/PulseNodeUpNodeFrontNode");
	
	// 1. Opening the node file.
	inFile = fopen(fileName,"rb");
	if(inFile == NULL)
	{
		printf("\n\n Can't open Nodes file %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	// 2. Reading the header information.
	fscanf(inFile, "%d", &PulsePointNode);
	printf("\n PulsePointNode = %d", PulsePointNode);
	fscanf(inFile, "%d", &UpNode);
	printf("\n UpNode = %d", UpNode);
	fscanf(inFile, "%d", &FrontNode);
	printf("\n FrontNode = %d", FrontNode);
	printf("\n");
	
	fclose(inFile);
	printf("\n PulsePointNode, UpNode, and FrontNode have been read in.\n");
}

/*
 This function 
 1. Opens the Bachmann's Bundle (BB) file.
 2. Reads the number of nodes in the BB.
 3. Allocating memory on both CPU hold BB.
 4. Reads the BB nodes.
 */
void readBachmannBundleFromFile()
{	
	FILE *inFile;
	int id;
	char fileName[256];
	
	// Generating the name of the file that holds the nodes.
	char directory[] = "./NodesMuscles/";
	strcpy(fileName, "");
	strcat(fileName, directory);
	strcat(fileName, NodesMusclesFileName);
	strcat(fileName, "/BachmannsBundle");
	
	// 1. Opening the file.
	inFile = fopen(fileName,"rb");
	if(inFile == NULL)
	{
		printf("\n\n Can't open Bachmann's Bundle file.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	// 2. Reading the header information.
	fscanf(inFile, "%d", &NumberOfNodesInBachmannsBundle);
	printf("\n NumberOfNodesInBachmannsBundle = %d", NumberOfNodesInBachmannsBundle);
	
	// 3. Allocating memory for the Bachmann's Bundle nodes.
	BachmannsBundle = (int*)malloc(NumberOfNodesInBachmannsBundle*sizeof(int));
	
	// 4. Reading the nodes that extend from the pulse node to create Bachmann's Bundle.
	for(int i = 0; i < NumberOfNodesInBachmannsBundle; i++)
	{
		fscanf(inFile, "%d ", &id);
		BachmannsBundle[i] = id;
	}
	
	fclose(inFile);
	printf("\n Bachmann's Bundle Nodes have been read in.\n");
}

/*
 This function 
 1. Opens the muscles file.
 2. Reads the number of muscles.
 3. Allocates memory to hold the muscles on the CPU and the GPU
 4. Sets all the muscles to their default or start values.
 5. Reads and connects the muscle to the two nodes it is connected to.
*/
void readAndConnectMusclesFromFile()
{	
	FILE *inFile;
	int id, idNode1, idNode2;
	char fileName[256];
    
	// Generating the name of the file that holds the muscles.
	char directory[] = "./NodesMuscles/";
	strcpy(fileName, "");
	strcat(fileName, directory);
	strcat(fileName, NodesMusclesFileName);
	strcat(fileName, "/Muscles");
	
	// 1. Opening the muscle file.
	inFile = fopen(fileName,"rb");
	if (inFile == NULL)
	{
		printf("\n\n Can't open Muscles file %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	// 2. Reading the header information.
	fscanf(inFile, "%d", &NumberOfMuscles);
	printf("\n NumberOfMuscles = %d", NumberOfMuscles);
	
	// 3. Allocating memory for the CPU and GPU muscles. 
	//Muscle = (muscleAttributesStructure*)malloc(NumberOfMuscles*sizeof(muscleAttributesStructure));
	cudaHostAlloc(&Muscle, NumberOfMuscles*sizeof(muscleAttributesStructure), cudaHostAllocDefault); // Making page locked memory on the CPU.
	cudaErrorCheck(__FILE__, __LINE__);
	
	cudaMalloc((void**)&MuscleGPU, NumberOfMuscles*sizeof(muscleAttributesStructure));
	cudaErrorCheck(__FILE__, __LINE__);

	// 4. Setting all muscles to their default settings; 
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		Muscle[i].nodeA = -1;
		Muscle[i].nodeB = -1;
		Muscle[i].apNode = -1;
		Muscle[i].isOn = false;
		Muscle[i].isEnabled = true;
		Muscle[i].timer = -1.0;
		Muscle[i].mass = -1.0;
		Muscle[i].naturalLength = -1.0;
		Muscle[i].relaxedStrength = -1.0;
		Muscle[i].compressionStopFraction = -1.0;
		Muscle[i].conductionVelocity = -1.0;
		Muscle[i].conductionDuration = -1.0;
		Muscle[i].refractoryPeriod = -1.0;
		Muscle[i].absoluteRefractoryPeriodFraction = -1.0;
		Muscle[i].contractionStrength = -1.0;
		
		// Setting all muscle colors to ready (red)
		Muscle[i].color.x = 1.0;
		Muscle[i].color.y = 0.0;
		Muscle[i].color.z = 0.0;
		Muscle[i].color.w = 0.0;
	}
	
	// 5. Reading in from the blender file what two nodes the muscle connects.
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		fscanf(inFile, "%d", &id);
		fscanf(inFile, "%d", &idNode1);
		fscanf(inFile, "%d", &idNode2);
		
		if(NumberOfMuscles <= id)
		{
			printf("\n\n You are trying to create a muscle that is out of bounds.");
			printf("\n The simulation has been terminated.\n\n");
			exit(0);
		}
		if(NumberOfNodes <= idNode1 || NumberOfNodes <= idNode2)
		{
			printf("\n\n You are trying to connect to a node that is out of bounds.");
			printf("\n The simulation has been terminated.\n\n");
			exit(0);
		}
		Muscle[id].nodeA = idNode1;
		Muscle[id].nodeB = idNode2;
	}
	
	fclose(inFile);
	printf("\n Blender generated muscles have been created.\n");
}

/*
 This function reads node and muscle data from a config-exported binary file.
 It appends the binary values into the existing model structs by filling fields
 that already exist in this model's node and muscle structures.
*/
void readNodesAndMusclesFromBinaryFile()
{
	FILE *inFile;
	char fileName[512];
	char *dot;
	struct stat fileStat;

	// Build the expected input path under the binary folder.
	strcpy(fileName, "./NodesMuscles/bin/");
	strcat(fileName, NodesMusclesFileName);

	// Enforce .bin extension for early detection of invalid file names and to avoid confusion with raw files
	dot = strrchr(NodesMusclesFileName, '.');
	if(dot == NULL || strcmp(dot, ".bin") != 0)
	{
		printf("\n\n Invalid binary input file name %s.", NodesMusclesFileName);
		printf("\n InputFileName in BasicSimulationSetup must end with .bin");
		printf("\n If you are trying to read in a raw file, make sure you run it through the config program and save it as a .bin file.");
		printf("\n To run the config program, run the command: ./runconfig in the terminal");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	// Check that the file physically exists before trying to open it.
	if(stat(fileName, &fileStat) != 0)
	{
		printf("\n\n Binary file %s does not exist.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	// Open in binary read mode.
	inFile = fopen(fileName, "rb");
	if(inFile == NULL)
	{
		printf("\n\n Can't open binary file %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	// Read and validate format version before reading any payload.
	int version = 0;
	fread(&version, sizeof(int), 1, inFile);
	if(version != 1)
	{
		printf("\n\n Unsupported binary version %d in %s.", version, fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	// Read global counts and orientation references
	fread(&NumberOfNodes, sizeof(int), 1, inFile);
	fread(&NumberOfMuscles, sizeof(int), 1, inFile);
	fread(&PulsePointNode, sizeof(int), 1, inFile);
	fread(&UpNode, sizeof(int), 1, inFile);
	fread(&FrontNode, sizeof(int), 1, inFile);

	printf("\n NumberOfNodes = %d", NumberOfNodes);
	printf("\n NumberOfMuscles = %d", NumberOfMuscles);
	printf("\n PulsePointNode = %d", PulsePointNode);
	printf("\n UpNode = %d", UpNode);
	printf("\n FrontNode = %d", FrontNode);

	// Reset cached binary node colors so we can store the colors from this file.
	if(BinaryNodeColors != NULL)
	{
		free(BinaryNodeColors);
		BinaryNodeColors = NULL;
	}
	BinaryNodeColors = (float4*)malloc(NumberOfNodes*sizeof(float4));
	if(BinaryNodeColors == NULL)
	{
		printf("\n\n Could not allocate node binary color storage.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	// Reset cached binary muscle colors so we can store the colors from this file.
	if(BinaryMuscleColors != NULL)
	{
		free(BinaryMuscleColors);
		BinaryMuscleColors = NULL;
	}
	BinaryMuscleColors = (float4*)malloc(NumberOfMuscles*sizeof(float4));
	if(BinaryMuscleColors == NULL)
	{
		printf("\n\n Could not allocate muscle binary color storage.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	// Start fresh; this counter is rebuilt while nodes are read.
	NumberOfNodesInBachmannsBundle = 0;

	// Allocate and initialize node structs with model defaults.
	cudaHostAlloc((void**)&Node, NumberOfNodes*sizeof(nodeAttributesStructure), cudaHostAllocDefault);
	cudaErrorCheck(__FILE__, __LINE__);
	cudaMalloc((void**)&NodeGPU, NumberOfNodes*sizeof(nodeAttributesStructure));
	cudaErrorCheck(__FILE__, __LINE__);

	for(int i = 0; i < NumberOfNodes; i++)
	{
		Node[i].position.x = 0.0;
		Node[i].position.y = 0.0;
		Node[i].position.z = 0.0;
		Node[i].position.w = 0.0;

		Node[i].velocity.x = 0.0;
		Node[i].velocity.y = 0.0;
		Node[i].velocity.z = 0.0;
		Node[i].velocity.w = 0.0;

		Node[i].force.x = 0.0;
		Node[i].force.y = 0.0;
		Node[i].force.z = 0.0;
		Node[i].force.w = 0.0;

		Node[i].mass = 0.0;
		Node[i].area = 0.0;
		Node[i].isBeatNode = false;
		Node[i].beatPeriod = -1.0;
		Node[i].beatTimer = -1.0;
		Node[i].isFiring = false;
		Node[i].isAblated = false;
		Node[i].isDrawNode = false;

		Node[i].color.x = 0.0;
		Node[i].color.y = 1.0;
		Node[i].color.z = 0.0;
		Node[i].color.w = 0.0;

		for(int j = 0; j < MUSCLES_PER_NODE; j++)
		{
			Node[i].muscle[j] = -1;
		}
	}

	// Read nodes in exact order used by config saveBinary().
	for(int i = 0; i < NumberOfNodes; i++)
	{
		int nodeType;
		fread(&nodeType, sizeof(int), 1, inFile);
		(void)nodeType;
		fread(&Node[i].position, sizeof(float4), 1, inFile);
		fread(Node[i].muscle, sizeof(int), MUSCLES_PER_NODE, inFile);
		fread(&BinaryNodeColors[i], sizeof(float4), 1, inFile);
	}

	// Allocate and initialize muscle structs with model defaults.
	cudaHostAlloc((void**)&Muscle, NumberOfMuscles*sizeof(muscleAttributesStructure), cudaHostAllocDefault);
	cudaErrorCheck(__FILE__, __LINE__);
	cudaMalloc((void**)&MuscleGPU, NumberOfMuscles*sizeof(muscleAttributesStructure));
	cudaErrorCheck(__FILE__, __LINE__);

	for(int i = 0; i < NumberOfMuscles; i++)
	{
		Muscle[i].nodeA = -1;
		Muscle[i].nodeB = -1;
		Muscle[i].apNode = -1;
		Muscle[i].isOn = false;
		Muscle[i].isEnabled = true;
		Muscle[i].timer = -1.0;
		Muscle[i].mass = -1.0;
		Muscle[i].naturalLength = -1.0;
		Muscle[i].relaxedStrength = -1.0;
		Muscle[i].compressionStopFraction = -1.0;
		Muscle[i].conductionVelocity = -1.0;
		Muscle[i].conductionDuration = -1.0;
		Muscle[i].refractoryPeriod = -1.0;
		Muscle[i].absoluteRefractoryPeriodFraction = -1.0;
		Muscle[i].contractionStrength = -1.0;

		Muscle[i].color.x = 1.0;
		Muscle[i].color.y = 0.0;
		Muscle[i].color.z = 0.0;
		Muscle[i].color.w = 0.0;
	}

	// Read muscles in exact order used by config saveBinary().
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		int muscleType;
		fread(&muscleType, sizeof(int), 1, inFile);
		(void)muscleType;
		fread(&Muscle[i].nodeA, sizeof(int), 1, inFile);
		fread(&Muscle[i].nodeB, sizeof(int), 1, inFile);
		fread(&Muscle[i].naturalLength, sizeof(float), 1, inFile);
		fread(&BinaryMuscleColors[i], sizeof(float4), 1, inFile);
	}

	//close file and print success message.
	fclose(inFile);
	printf("\n Binary file %s has been read in.\n", fileName);
}

/*
 This function loads each node structure with all the muscles it is connected to.
*/
void linkNodesToMuscles()
{	
	int k;
	// Each node will have a list of the muscles it is attached to.
	for(int i = 0; i < NumberOfNodes; i++)
	{
		k = 0;
		for(int j = 0; j < NumberOfMuscles; j++)
		{
			if(Muscle[j].nodeA == i || Muscle[j].nodeB == i) // Checking to see if either end of the muscle is attached to node i.
			{
				if(MUSCLES_PER_NODE < k) // Making sure we do not go out of bounds.
				{
					printf("\n\n Number of muscles connected to node %d is larger than the allowed number of", i);
					printf("\n muscles connected to a single node.");
					printf("\n If this is not a mistake increase MUSCLES_PER_NODE in the header.h file.");
					printf("\n The simulation has been terminated.\n\n");
					exit(0);
				}
				Node[i].muscle[k] = j;
				k++;
			}
		}
	}
	printf("\n Nodes have been linked to muscles. \n");
}

/*
 This function: 
 1: Uses the Box-Muller method to create a standard normal random number from two uniform random numbers.
 2: Sets the standard deviation to what was input.
 3: Checks to see if the random number is between the desired numbers. If not throw it away and choose again.
*/
double croppedRandomNumber(double stddev, double left, double right)
{
	double temp1, temp2;
	double randomNumber;
	bool test = false;
			
	while(test == false)
	{
		// Getting two uniform random numbers in [0,1]
		temp1 = ((double) rand() / (RAND_MAX));
		temp2 = ((double) rand() / (RAND_MAX));
		
		// Using Box-Muller to get a standard normally distributed random number (mean = 0, stddev = 1)
		randomNumber = sqrt(-2.0 * log(temp1))*cos(2.0*PI*temp2);
		
		// Setting its Standard Deviation to the the desired value. 
		randomNumber *= stddev;
		
		// Chopping the random number between left and right.  
		if(randomNumber < left || right < randomNumber) test = false;
		else test = true;
	}
	return(randomNumber);	
}

/*
 This function 
 1. Finds the average radius of the LA which we will use as the radius of the LA.
 2. Finds the mass of the LA.
*/
void findRadiusAndMassOfLeftAtrium()
{
        // 1. Finding the average radius of the LA from its nodes and setting this as the radius of the LA.
	double averageRadius = 0.0;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		averageRadius += sqrt(Node[i].position.x*Node[i].position.x + Node[i].position.y*Node[i].position.y + Node[i].position.z*Node[i].position.z);
	}
	averageRadius /= (double)NumberOfNodes;
	RadiusOfLeftAtrium = averageRadius;
	printf("\n RadiusOfLeftAtrium = %f millimeters", RadiusOfLeftAtrium);
	
	// 2. Setting the mass of the LA. 
	double innerVolumeOfLA = (4.0*PI/3.0)*averageRadius*averageRadius*averageRadius;
	printf("\n Inner volume of LA = %f cubic millimeters", innerVolumeOfLA);
	double outerRadiusOfLA = averageRadius/(1.0 - WallThicknessFraction);
	double outerVolumeOfLA = (4.0*PI/3.0)*outerRadiusOfLA*outerRadiusOfLA*outerRadiusOfLA;
	double volumeOfTissue = outerVolumeOfLA - innerVolumeOfLA;
	MassOfLeftAtrium = volumeOfTissue*MyocardialTissueDensity;
	printf("\n Mass of LA = %f grams", MassOfLeftAtrium);
	
	printf("\n LA radius and mass has been set.\n");
}

/*
 In this function, we set the remaining value of the nodes and muscle which were not already 
 set in the setNodesFromBlenderFile(), the setMusclesFromBlenderFile(), and the linkNodesToMuscles() functions.
 1: Checking to make sure LA radius and mass are set before we use them to set Node and Muscle attributes.
 2: Setting the pulse point node.
 3: Then, we find the length of each individual muscle and sum these up to find the total length of all muscles that represent
    the left atrium. 
 4: This allows us to find the fraction of a single muscle's length compared to the total muscle lengths. We can now multiply this 
    fraction by the mass of the left atrium to get the mass on an individual muscle. 
 5: Next, we use the muscle mass to find the mass of each node by taking half (each muscle is connected to two nodes) the mass of all 
    muscles connected to it. We can then use the ratio of node masses (like we used the ratio of muscle length in 2) to 
    find the area of each node. Area is used to get a force on the node from the LA pressure.
 6: Here we set the base muscle attributes. 
    a: Setting the muscles conduction velocity. 
    b: Setting the muscles conduction duration (How long it takes for a signal to travel across the muscle).
    c: Setting the muscle's refractory period.
    d: Setting the muscle's absolute refractory period.
    e: Setting the muscle's contraction strength.
      The myocyte force per mass ratio is calculated by treating a myocyte as a cylinder. 
      In the for loop we add some small random fluctuations to these values so the simulation can have some stochastic behavior. 
      If you do not want any stochastic behavior simply set MyocyteForcePerMassSTD to zero in the simulationsetup file.
      The strength is also scaled using the scaling read in from the simulationSetup file. The scaling is used so the user
      can adjust the standard muscle attributes to perform as desired in their simulation. A value of 1.0 adds no scaling.
    f: Setting the muscle's compression stop fraction (The max percent of the muscles length that is lost in contraction).
     Note: Muscles do not have mass in the simulation. All the mass is carried in the nodes. Muscles were given mass here to be able to
     generate the node masses and area. We carry the muscle masses forward in the event that we need to generate a muscle ratio in 
     future updates to the program. 
 7: Setting all the atributes of BB. 
 8: Setting all the atributes of the LAA.
 9: Setting all the atributes of the PV.
*/
void setRemainingNodeAndMuscleAttributes()
{	
	// 1:
	if(RadiusOfLeftAtrium < 0.0 || MassOfLeftAtrium < 0.0) // They are intiallized at -1.0.
	{
	      printf("\n You are trying to set Node and Muscle attributes before LA radius and mass are set.");
	      printf("\n The simulation has been terminated.\n\n");
	      exit(0);
	}
	
	// 2: This is the pulse point node that generates the beat.
	Node[PulsePointNode].isBeatNode = true;
	Node[PulsePointNode].beatPeriod = BeatPeriod;
	Node[PulsePointNode].beatTimer = BeatPeriod; // Set the time to BeatPeriod so it will kickoff a beat as soon as it starts.
	
	// 3:
	double dx, dy, dz, d;
	double totalLengthOfAllMuscles = 0.0;
	for(int i = 0; i < NumberOfMuscles; i++)
	{	
		dx = Node[Muscle[i].nodeA].position.x - Node[Muscle[i].nodeB].position.x;
		dy = Node[Muscle[i].nodeA].position.y - Node[Muscle[i].nodeB].position.y;
		dz = Node[Muscle[i].nodeA].position.z - Node[Muscle[i].nodeB].position.z;
		d = sqrt(dx*dx + dy*dy + dz*dz);
		Muscle[i].naturalLength = d; // The natural length is how far apart its two ends are at rest.
		totalLengthOfAllMuscles += d;
	}
		
	// 4: Calculating the mass of each individual muscle.
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		Muscle[i].mass = MassOfLeftAtrium*(Muscle[i].naturalLength/totalLengthOfAllMuscles);
	}

	// 5: Calculating a mass for each node.
	double surfaceAreaOfLeftAtrium = 4.0*PI*RadiusOfLeftAtrium*RadiusOfLeftAtrium;
	double connectedMuscleMass;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		connectedMuscleMass = 0.0;
		for(int j = 0; j < MUSCLES_PER_NODE; j++)
		{
			if(Node[i].muscle[j] != -1)
			{
				connectedMuscleMass += Muscle[Node[i].muscle[j]].mass;
			}
		}
		Node[i].mass = connectedMuscleMass/2.0;
		Node[i].area = surfaceAreaOfLeftAtrium*(Node[i].mass/MassOfLeftAtrium);
	}
	
	// 6:
	double stddev, left, right;
 	double radius = MyocyteDiameter/2.0;
 	double myocyteVolume = PI*radius*radius*MyocyteLength;
 	double myocyteMass = myocyteVolume*MyocardialTissueDensity;
 	MyocyteForcePerMassFraction = MyocyteContractionForce/myocyteMass;
        
	for(int i = 0; i < NumberOfMuscles; i++)
	{	
	        // a: Setting the muscles conduction velocity.
		stddev = MuscleConductionVelocitySTD;
		left = -MuscleConductionVelocitySTD;
		right = MuscleConductionVelocitySTD;
		Muscle[i].conductionVelocity = BaseMuscleConductionVelocity + croppedRandomNumber(stddev, left, right);
		
		// b: Setting the muscles conduction duration (How long it takes for a signal to travel across the muscle).
		Muscle[i].conductionDuration = Muscle[i].naturalLength/Muscle[i].conductionVelocity;
		
		// c: Setting the muscle's refractory period.
		stddev = MuscleRefractoryPeriodSTD;
		left = -MuscleRefractoryPeriodSTD;
		right = MuscleRefractoryPeriodSTD;	
		Muscle[i].refractoryPeriod = BaseMuscleRefractoryPeriod + croppedRandomNumber(stddev, left, right);
		
		// d: Setting the muscle's absolute refractory period.
		stddev = AbsoluteRefractoryPeriodFractionSTD;
		left = -AbsoluteRefractoryPeriodFractionSTD;
		right = AbsoluteRefractoryPeriodFractionSTD;
		Muscle[i].absoluteRefractoryPeriodFraction = BaseAbsoluteRefractoryPeriodFraction + croppedRandomNumber(stddev, left, right);
		
		// e: Setting the muscle's contraction strength.
		stddev = MyocyteForcePerMassSTD;
		left = -MyocyteForcePerMassSTD;
		right = MyocyteForcePerMassSTD;
		Muscle[i].contractionStrength = MyocyteForcePerMassMultiplier*(MyocyteForcePerMassFraction + croppedRandomNumber(stddev, left, right))*Muscle[i].mass;
		
		/* ???
		// If you want to use cross section for strength use this. But I had a lot of problems with it and had to move on to
		// more important things. I may readdress this when I get time.
		// We will need to read in MyocyteForcePerCrossSectionalArea and MyocyteForcePerCrossSectionalAreaSTD from a setup file.
		
		// Cross sectional area is Mass/(Length*Density) 
		double MyocyteForcePerCrossSectionalAreaSTD
		stddev = MyocyteForcePerCrossSectionalAreaSTD;
		left = -MyocyteForcePerCrossSectionalAreaSTD;
		right = MyocyteForcePerCrossSectionalAreaSTD;
	        double CrossSectionalArea = (double)Muscle[i].mass/((double)Muscle[i].naturalLength*(double)MyocardialTissueDensity);
	        double MyocyteForcePerCrossSectionalArea = 0.35; // Got this from a paper and it does make the values close to what we are getting with mass.
	        double contractionStrength = MyocyteForcePerMassMultiplier*(MyocyteForcePerCrossSectionalArea + croppedRandomNumber(stddev, left, right))*CrossSectionalArea;
	        Muscle[i].contractionStrength = contractionStrength;
	        */
		
		Muscle[i].relaxedStrength = MuscleRelaxedStrengthFraction*Muscle[i].contractionStrength;
		
		// f: Setting the muscle's compression stop fraction (The max percent of the muscles length that is lost in contraction).
		stddev = MuscleCompressionStopFractionSTD;
		left = -MuscleCompressionStopFractionSTD;     
		right = MuscleCompressionStopFractionSTD;         
		Muscle[i].compressionStopFraction = MuscleCompressionStopFraction + croppedRandomNumber(stddev, left, right);
	}
	
	// 7: Setting all the atributes of BB.
	// !! Make sure this loop is after the basic muscle loop because all values are created as a multiple of those values.
	int id, id2;
	for(int i = -1; i < NumberOfNodesInBachmannsBundle; i++)
	{	
	        // a: Coloring the nodes. 
	        //    The pulse point node is technically the first node in BB but it has other functions so it not an index in the BB vector.
	        //    But it is colored the same.
		if(i == -1)
		{
			id = PulsePointNode;
			Node[id].color.x = BachmannColor.x;
			Node[id].color.y = BachmannColor.y;
			Node[id].color.z = BachmannColor.z;
			Node[id].isDrawNode = false; // The pulse node is always drawn as a sphere so no need to also draw it as a point.
		}
		else
		{
			id = BachmannsBundle[i];
			Node[id].color.x = BachmannColor.x;
			Node[id].color.y = BachmannColor.y;
			Node[id].color.z = BachmannColor.z;
			Node[id].isDrawNode = true;
		}
		
		// b: Adjusting the values that a muscle connected to BB nodes will have.
		for(int k = 0; k < MUSCLES_PER_NODE; k++)
		{
			id2 = Node[id].muscle[k];
			// If a node is connected to a muscle it will have a positive number. 
			// If it is -1 it means you are past the number of muscle that node is connected to.
			if(id2 != -1) 
			{
				for(int j = i+1; j < NumberOfNodesInBachmannsBundle; j++)
				{
					for(int l = 0; l < MUSCLES_PER_NODE; l++)
					{
						if(Node[BachmannsBundle[j]].muscle[l] == id2)
						{
							Muscle[id2].color.x = BachmannColor.x;
							Muscle[id2].color.y = BachmannColor.y;
							Muscle[id2].color.z = BachmannColor.z;
							Muscle[id2].conductionDuration /= BachmannsBundleMultiplier;
						}
					}
				
				}
			}
		}
	}
	
	// 8: Setting all the atributes of the LAA.
	// !! Make sure this loop is after the basic muscle loop because all values are created as a multiple of those values.
	/*
	for(int i = 0; i < NumberOfNodesInLAA; i++)
	{
	
	}
	*/
	
	// 9: Setting all the atributes of the PV.
	// !! Make sure this loop is after the basic muscle loop because all values are created as a multiple of those values.
	/*
	for(int i = 0; i < NumberOfPVNodes; i++)
	{
	
	}
	*/
	
	printf("\n All node and muscle attributes have been set.\n");
}

/*
 This function loads all the node and muscle attributes from a previous run file that was saved.
*/
void getNodesandMusclesFromPreviousRun()
{
	FILE *inFile;
	char fileName[256];
	
	strcpy(fileName, "");
	strcat(fileName,"./PreviousRunsFile/");
	strcat(fileName,PreviousRunFileName);
	strcat(fileName,"/run");

	inFile = fopen(fileName,"rb");
	if(inFile == NULL)
	{
		printf("\n\n Can't open PreviousRunsFile %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	//settingFile = fopen("run", "wb");
  	
        fread(&NumberOfNodes, sizeof(int), 1, inFile);
        // Creating memory space for the nodes on the CPU and GPU
        cudaHostAlloc(&Node, NumberOfNodes*sizeof(nodeAttributesStructure), cudaHostAllocDefault); // Making page locked memory on the CPU.
        cudaErrorCheck(__FILE__, __LINE__);
        cudaMalloc((void**)&NodeGPU, NumberOfNodes*sizeof(nodeAttributesStructure));
        cudaErrorCheck(__FILE__, __LINE__);
        fread(Node, sizeof(nodeAttributesStructure), NumberOfNodes, inFile);
  	
        int linksPerNode = MUSCLES_PER_NODE;
        fread(&linksPerNode, sizeof(int), 1, inFile);
        if(linksPerNode != MUSCLES_PER_NODE)
        {
              printf("\n\n The number Of muscle per node do not match.");
              printf("\n You will have to set the #define MUSCLES_PER_NODE");
              printf("\n to %d in header.h then recompile the code.", linksPerNode);
              printf("\n The simulation has been terminated.\n\n");
              exit(0);
        }
  	
        fread(&NumberOfMuscles, sizeof(int), 1, inFile);
        // Creating memory space for the muscles on the CPU and GPU
        cudaHostAlloc(&Muscle, NumberOfMuscles*sizeof(muscleAttributesStructure), cudaHostAllocDefault); // Making page locked memory on the CPU.
        cudaErrorCheck(__FILE__, __LINE__);
        cudaMalloc((void**)&MuscleGPU, NumberOfMuscles*sizeof(muscleAttributesStructure));
        cudaErrorCheck(__FILE__, __LINE__);
        fread(Muscle, sizeof(muscleAttributesStructure), NumberOfMuscles, inFile);

        fread(&NumberOfNodesInBachmannsBundle, sizeof(int), 1, inFile);
        // Allocating memory for the Bachmann's Bundle nodes.
        BachmannsBundle = (int*)malloc(NumberOfNodesInBachmannsBundle*sizeof(int));
        fread(BachmannsBundle, sizeof(int), NumberOfNodesInBachmannsBundle, inFile);
  	
  	// To keep the contraction state what was readin from the BasicSimulationSetup file not what the state was
  	// when the simulation was saved we save it in a temp, overwrite it then restore it.
        fread(&Simulation, sizeof(Simulation), 1, inFile);
  	
        fread(&PulsePointNode, sizeof(int), 1, inFile);
        fread(&UpNode, sizeof(int), 1, inFile);
        fread(&FrontNode, sizeof(int), 1, inFile);
  	
        fread(&ViewName, sizeof(char), 256, inFile);
  	
        fread(&RefractoryPeriodAdjustmentMultiplier, sizeof(float), 1, inFile);
        fread(&MuscleConductionVelocityAdjustmentMultiplier, sizeof(float), 1, inFile);
        
        fread(&RadiusOfLeftAtrium, sizeof(double), 1, inFile);
        fread(&MassOfLeftAtrium, sizeof(double), 1, inFile);
        fread(&MyocyteForcePerMassFraction, sizeof(double), 1, inFile);
  	
        fread(&CenterOfSimulation, sizeof(float4), 1, inFile);
        fread(&AngleOfSimulation, sizeof(float4), 1, inFile);
        
        fread(&RunTime, sizeof(double), 1, inFile);
        
	fclose(inFile);
	
	printf("\n Nodes and Muscles have been read in from %s.\n", fileName);	
}

/*
 This function sets any remaining parameters that are not part of the nodes or muscles structures.
 It also sets or initializes the run parameters for this run.
*/
void setRemainingParameters()
{	
	bool isBinaryInput = false;
	char *extension = strrchr(NodesMusclesFileName, '.');
	if(extension != NULL && strcmp(extension, ".bin") == 0)
	{
		isBinaryInput = true;
	}

	// If this is a new run these values are set hre. If it is a previous run these values will aready be read in.
	if (NodesMusclesFileOrPreviousRunsFile == 0) 
	{
	      RunTime = 0.0;
	      
	      RefractoryPeriodAdjustmentMultiplier = 1.0;
	      MuscleConductionVelocityAdjustmentMultiplier = 1.0;
	      
	      CenterOfSimulation.x = 0.0;
	      CenterOfSimulation.y = 0.0;
	      CenterOfSimulation.z = 0.0;
	      CenterOfSimulation.w = 0.0;
	      
	      AngleOfSimulation.x = 0.0;
	      AngleOfSimulation.y = 1.0;
	      AngleOfSimulation.z = 0.0;
	      AngleOfSimulation.w = 0.0;

		Simulation.isPaused = true;
		Simulation.isInAblateMode = false;
		Simulation.isInEctopicBeatMode = false;
		Simulation.isInEctopicEventMode = false;
		Simulation.isInAdjustMuscleAreaMode = false;
		Simulation.isInAdjustMuscleLineMode = false;
		Simulation.isInFindNodeMode = false;
		Simulation.isInMouseFunctionMode = false;
		Simulation.isRecording = false;
		//Simulation.ContractionisOn = false; //This is set in the BasicSimulationSetup file.
		Simulation.ViewFlag = 1;
		Simulation.DrawNodesFlag = 0;
		Simulation.DrawFrontHalfFlag = 0;
		Simulation.ShowMuscleTypesFlag = false;
		Simulation.nodesFound = false;
		Simulation.frontNodeIndex = -1;
		Simulation.topNodeIndex = -1;
		// Simulation.guiCollapsed = false; //This is set in viewDrawAndTerminalFuctions.h/createGUI().
		
		if(!isBinaryInput)
		{
			setView(6); //Set deafult view only if not loading from a binary snapshot.
		}
	}
	
	HitMultiplier = 0.03;
	MouseZ = RadiusOfLeftAtrium;
	MouseX = 0.0;
	MouseY = 0.0;
	ScrollSpeedToggle = 1;
	ScrollSpeed = 1.0;
	MouseWheelPos = 0;
	RecenterCount = 0;
	RecenterRate = 10;
}
		
/*
 This code 
 1: Checks to see if the electrical signal goes through the muscle faster than the refractory period.
    If it does not a muscle could fire itself and the signal would just bounce back and forth in the muscle.
    If this is true we just kill the muscle and move on.
 2: If a muscle's relaxed strength is greater than it contraction strength something must have gotten entered
    wrong in the setup file. Here we kill the muscle and move on but we might need to kill the simulation.
 3: If the muscle can contract past half its natural length or cannot contract down to its natural length
    something is wrong in the setup simulation file. Here we kill the muscle and move on.
 4: The muscle's absolute refoctory period should be greater than half the refractory period and less than the refractory period. 
    If not something is wrong. Here we kill the muscle and move on.
 5: If the muscle's contraction strength is negative something is wrong. Here we kill the muscle and move on.
    
 We left each if statement as a stand alone unit in case the user wants to perform a different act in a selected
 if statement. We could have set a flag and just killed the the muscle after all checks, but this gives move
 flexibility for future directions. 
*/
void checkMuscle(int muscleId)
{
	// 1:
	if(Muscle[muscleId].refractoryPeriod < Muscle[muscleId].conductionDuration)
	{
	 	printf("\n\n Refractory period is shorter than the contraction duration in muscle number %d", muscleId);
	 	printf("\n Muscle %d will be disabled. \n", muscleId);
	 	Muscle[muscleId].isEnabled = false;
	 	Muscle[muscleId].color.x = DeadColor.x;
		Muscle[muscleId].color.y = DeadColor.y;
		Muscle[muscleId].color.z = DeadColor.z;
		Muscle[muscleId].color.w = 1.0;
	} 
	// 2:							
	if(Muscle[muscleId].contractionStrength < Muscle[muscleId].relaxedStrength)
	{
	 	printf("\n\n The relaxed repulsion strength of muscle %d is greater than its contraction strength. Rethink your parameters.", muscleId);
	 	printf("\n Muscle %d will be disabled. \n", muscleId);
	 	Muscle[muscleId].isEnabled = false;
	 	Muscle[muscleId].color.x = DeadColor.x;
		Muscle[muscleId].color.y = DeadColor.y;
		Muscle[muscleId].color.z = DeadColor.z;
		Muscle[muscleId].color.w = 1.0;
	} 
	// 3:
	if(Muscle[muscleId].compressionStopFraction < 0.5 || 1.0 < Muscle[muscleId].compressionStopFraction)
	{
		printf("\n\n The compression Stop Fraction for muscle %d is %f. Rethink your parameters.", muscleId, Muscle[muscleId].compressionStopFraction);
	 	printf("\n Muscle %d will be disabled. \n", muscleId);
	 	Muscle[muscleId].isEnabled = false;
	 	Muscle[muscleId].color.x = DeadColor.x;
		Muscle[muscleId].color.y = DeadColor.y;
		Muscle[muscleId].color.z = DeadColor.z;
		Muscle[muscleId].color.w = 1.0;
	}
	// 4:
	if(Muscle[muscleId].absoluteRefractoryPeriodFraction < 0.5 || 1.0 < Muscle[muscleId].absoluteRefractoryPeriodFraction)
	{
		printf("\n\n The absolute refractory period for muscle %d is %f. Rethink your parameters.", muscleId, Muscle[muscleId].compressionStopFraction);
	 	printf("\n Muscle %d will be disabled. \n", muscleId);
	 	Muscle[muscleId].isEnabled = false;
	 	Muscle[muscleId].color.x = DeadColor.x;
		Muscle[muscleId].color.y = DeadColor.y;
		Muscle[muscleId].color.z = DeadColor.z;
		Muscle[muscleId].color.w = 1.0;
	}
	// 5:
	if(Muscle[muscleId].contractionStrength < 0.0)
	{
		printf("\n\n The contraction strength for muscle %d is %f. Rethink your parameters.", muscleId, Muscle[muscleId].compressionStopFraction);
	 	printf("\n Muscle %d will be disabled. \n", muscleId);
	 	Muscle[muscleId].isEnabled = false;
	 	Muscle[muscleId].color.x = DeadColor.x;
		Muscle[muscleId].color.y = DeadColor.y;
		Muscle[muscleId].color.z = DeadColor.z;
		Muscle[muscleId].color.w = 1.0;
	}
}

