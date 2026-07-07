#ifndef SETNODESNMUSCLES_H
#define SETNODESNMUSCLES_H

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
 void readMusclesFromFile();
 void linkNodesToMuscles();
 double croppedRandomNumber(double, double, double);
 void setRemainingNodeAndMuscleAttributes();
 void getNodesandMusclesFromPreviousRun();
 void setRemainingParameters();
 void checkMuscle(int);
*/

float4 getMuscleColorFromType(int type);
		
/*
 This function 
 1. Opens the node file.
 2. Finds the number of nodes, the pulse node, the up and front nodes.
 3. Allocates memory to hold the nodes on the CPU and the GPU
 4. Sets all the nodes to their default or start values.
 5. Reads and assigns the node positions from the node file.
 6. Sets the pulse node.
*/
void readNodesFromFile()
{	
	FILE *inFile;
	float x, y, z;
	int id, nodeType;
	char fileName[256];

	
	// Generating the name of the file that holds the nodes.
	char directory[] = "../NodesMuscles/raw/";
	strcpy(fileName, "");
	strcat(fileName, directory);
	strcat(fileName, NodesMusclesFileName);
	strcat(fileName, "/Nodes");
	
	// 1. Opening the node file.
	inFile = fopen(fileName,"r");
	if(inFile == NULL)
	{
		printf("\n\n Can't open Nodes file %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	// 2. Reading the header information.
	fscanf(inFile, "%d", &NumberOfNodes);
	printf("\n NumberOfNodes = %d", NumberOfNodes);
	fscanf(inFile, "%d", &PulsePointNode);
	printf("\n PulsePointNode = %d", PulsePointNode);
	fscanf(inFile, "%d", &UpNode);
	printf("\n UpNode = %d", UpNode);
	fscanf(inFile, "%d", &FrontNode);
	printf("\n FrontNode = %d", FrontNode);

	// No Bachmann's Bundle file in this flow.
	NumberOfNodesInBachmannsBundle = 0;
	
	// 3. Allocating memory for the CPU and GPU nodes. 
	cudaHostAlloc((void**)&Node, NumberOfNodes*sizeof(nodeAttributesStructure), cudaHostAllocDefault); // Making page locked memory on the CPU.
	//cudaErrorCheck(__FILE__, __LINE__);
	
	
	// 4. Setting all nodes to zero or their default settings; 
	for(int i = 0; i < NumberOfNodes; i++)
	{
		Node[i].position.x = 0.0;
		Node[i].position.y = 0.0;
		Node[i].position.z = 0.0;
		Node[i].position.w = 0.0;
		
		// Setting all node colors to not ablated 
		Node[i].color.x = 0.0;
		Node[i].color.y = 1.0;
		Node[i].color.z = 0.0;
		Node[i].color.w = 0.0;

		Node[i].mass = 0.005266; // We took the average mass per node from the original program. Mass is only used to calculate COM for rotations in this program so any number should work here.
		Node[i].type = 0; // Setting the type to 0 for all nodes. We will use this to flag special nodes, like the pulse node and the bachmann's bundle nodes.	
		for(int j = 0; j < MUSCLES_PER_NODE; j++)
		{
			Node[i].muscle[j] = -1; // -1 sets the muscle to not used.
		}
	}
	
	printf("\n\nFile %s has been opened and memory has been allocated for the nodes.\n", fileName);

	// 5. Reading in the nodes positions.
	// Format: id type x y z
	for(int i = 0; i < NumberOfNodes; i++)
	{
		fscanf(inFile, "%d %d %f %f %f", &id, &nodeType, &x, &y, &z);

		Node[id].position.x = x;
		Node[id].position.y = y;
		Node[id].position.z = z;
		Node[id].type = nodeType;
		// Color nodes by type for debugging/visual validation.
		Node[id].color = getColorFromType(nodeType);
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
   1: This for loop finds all the nearest neighbor distances and then it calculates the average of this value. 
      This get a sense of how close nodes are in general. If you have more nodes they arvoid readPulseUpAndFrontNodesFromFile()e going to be 
      closer together, this number just gets you a scale to compare to.
   2: This for loop checks to see if two nodes are closer than an cutoffDivider times smaller than the 
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
	
	// 1: Finding average nearest neighbor distance.
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
	
	// 3: Terminating the simulation if nodes were flagged.
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
 2. Then reads in and sets the globals:PulsePointNode, UpNode, and FrontNode.
 3. Sets the pulse node.
*/
void readPulseUpAndFrontNodesFromFile()
{	
	// Pulse/Up/Front are read from the Nodes file header.
}

/*
 This function 
 1. Opens the Bachmann's Bundle (BB) file.
 2. Reads the number of nodes in the BB.
 3. Allocating memory on both CPU and GPU to hold BB.
 4. Reads the BB nodes.
 */
void readBachmannBundleFromFile()
{	
	// Bachmann's Bundle file is not used in this flow.
}

/*
 This function 
 1. Opens the muscles file.
 2. Reads the number of muscles.
 3. Allocates memory to hold the muscles on the CPU and the GPU
 4. Sets all the muscles to their default or start values.
 5. Reads and connects the muscle to the two nodes it is connected to.
*/
void readMusclesFromFile()
{	
	FILE *inFile;
	int id, idNode1, idNode2, muscleType;
	char fileName[256];
    
	// Generating the name of the file that holds the muscles.
	char directory[] = "../NodesMuscles/raw/";
	strcpy(fileName, "");
	strcat(fileName, directory);
	strcat(fileName, NodesMusclesFileName);
	strcat(fileName, "/Muscles");
	
	// Opening the muscle file.
	inFile = fopen(fileName,"r");
	if (inFile == NULL)
	{
		printf("\n\n Can't open Muscles file %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	
	fscanf(inFile, "%d", &NumberOfMuscles);
	printf("\n NumberOfMuscles = %d", NumberOfMuscles);
	
	// Allocating memory for the CPU and GPU muscles. 
	//Muscle = (muscleAttributesStructure*)malloc(NumberOfMuscles*sizeof(muscleAttributesStructure));
	cudaHostAlloc(&Muscle, NumberOfMuscles*sizeof(muscleAttributesStructure), cudaHostAllocDefault); // Making page locked memory on the CPU.
	//cudaErrorCheck(__FILE__, __LINE__);
	
	// Setting all muscles to their default settings; 
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		Muscle[i].type = 0;
		Muscle[i].nodeA = -1;
		Muscle[i].nodeB = -1;

		// Setting all muscle colors to default color (red)
		Muscle[i].color.x = 1.0;
		Muscle[i].color.y = 0.0;
		Muscle[i].color.z = 0.0;
		Muscle[i].color.w = 0.0;
	}
	
	// Reading in from the blender file what two nodes the muscle connects.
	// Format: id type nodeA nodeB
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		if(fscanf(inFile, "%d %d %d %d", &id, &muscleType, &idNode1, &idNode2) != 4)
		{
			printf("\n\n Invalid muscle format. Expected: id type nodeA nodeB.");
			printf("\n The simulation has been terminated.\n\n");
			exit(0);
		}
		
		if(id < 0 || NumberOfMuscles <= id)
		{
			printf("\n\n You are trying to create a muscle that is out of bounds.");
			printf("\n The simulation has been terminated.\n\n");
			exit(0);
		}
		if(idNode1 < 0 || idNode2 < 0 || NumberOfNodes <= idNode1 || NumberOfNodes <= idNode2)
		{
			printf("\n\n You are trying to connect to a node that is out of bounds.");
			printf("\n The simulation has been terminated.\n\n");
			exit(0);
		}
		Muscle[id].type = muscleType;
		Muscle[id].nodeA = idNode1;
		Muscle[id].nodeB = idNode2;
	}
	
	fclose(inFile);
	printf("\n Blender generated muscles have been created.\n");
}

/*
 Reads node/muscle data from a config-exported binary file.
 If NodesMusclesFileName contains .bin, it is treated as a filename under ../NodesMuscles/bin/.
*/
void readNodesAndMusclesFromBinaryFile()
{
	FILE *inFile;
	char fileName[512];
	char *dot;

	strcpy(fileName, "../NodesMuscles/bin/");
	strcat(fileName, NodesMusclesFileName);

	dot = strrchr(fileName, '.');
	if(dot == NULL || strcmp(dot, ".bin") != 0)
	{
		strcat(fileName, ".bin");
	}

	inFile = fopen(fileName, "rb");
	if(inFile == NULL)
	{
		printf("\n\n Can't open binary file %s.", fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	int version = 0;
	fread(&version, sizeof(int), 1, inFile);
		if(version != 1)
	{
		printf("\n\n Unsupported binary version %d in %s.", version, fileName);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}

	fread(&NumberOfNodes, sizeof(int), 1, inFile);
	fread(&NumberOfMuscles, sizeof(int), 1, inFile);
	fread(&PulsePointNode, sizeof(int), 1, inFile);
	fread(&UpNode, sizeof(int), 1, inFile);
	fread(&FrontNode, sizeof(int), 1, inFile);

	NumberOfNodesInBachmannsBundle = 0;

	cudaHostAlloc((void**)&Node, NumberOfNodes*sizeof(nodeAttributesStructure), cudaHostAllocDefault);
	for(int i = 0; i < NumberOfNodes; i++)
	{
		Node[i].position.x = 0.0;
		Node[i].position.y = 0.0;
		Node[i].position.z = 0.0;
		Node[i].position.w = 0.0;
		Node[i].color.x = 0.0;
		Node[i].color.y = 1.0;
		Node[i].color.z = 0.0;
		Node[i].color.w = 0.0;
		Node[i].mass = 0.005266;
		Node[i].type = 0;
		for(int j = 0; j < MUSCLES_PER_NODE; j++)
		{
			Node[i].muscle[j] = -1;
		}
	}

	for(int i = 0; i < NumberOfNodes; i++)
	{
		fread(&Node[i].type, sizeof(int), 1, inFile);
		fread(&Node[i].position, sizeof(float4), 1, inFile);
		fread(Node[i].muscle, sizeof(int), MUSCLES_PER_NODE, inFile);
		fread(&Node[i].color, sizeof(float4), 1, inFile);
	}

	cudaHostAlloc(&Muscle, NumberOfMuscles*sizeof(muscleAttributesStructure), cudaHostAllocDefault);
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		Muscle[i].type = 0;
		Muscle[i].nodeA = -1;
		Muscle[i].nodeB = -1;
		Muscle[i].color.x = 1.0;
		Muscle[i].color.y = 0.0;
		Muscle[i].color.z = 0.0;
		Muscle[i].color.w = 0.0;
	}

	for(int i = 0; i < NumberOfMuscles; i++)
	{
		float naturalLength;
		fread(&Muscle[i].type, sizeof(int), 1, inFile);
		fread(&Muscle[i].nodeA, sizeof(int), 1, inFile);
		fread(&Muscle[i].nodeB, sizeof(int), 1, inFile);
		fread(&naturalLength, sizeof(float), 1, inFile);
		fread(&Muscle[i].color, sizeof(float4), 1, inFile);
	}

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
 Returns priority for a node type when resolving mixed-type muscles.
 Returns -1 for unknown types.
*/
int getTypePriority(int nodeType)
{
	const int PRIORITY_LA = 1;
	const int PRIORITY_BB = 2;
	const int PRIORITY_LAA = 3;
	const int PRIORITY_XT = 4;
	const int PRIORITY_PV = 5;
	const int PRIORITY_MV = 6;

	if(nodeType == NODE_TYPE_STANDARD) return PRIORITY_LA;
	if(nodeType == NODE_TYPE_BACHMANN_BUNDLE) return PRIORITY_BB;
	if(nodeType == NODE_TYPE_APPENDAGE) return PRIORITY_LAA;
	if(nodeType == NODE_TYPE_SCAR_TISSUE) return PRIORITY_XT;
	if(nodeType == NODE_TYPE_PULMONARY_VEINS) return PRIORITY_PV;
	if(nodeType == NODE_TYPE_MITRAL_VALVE) return PRIORITY_MV;

	return -1;
}

/*
 Returns the display color for a muscle type.
*/
float4 getMuscleColorFromType(int type)
{
	if(type == NODE_TYPE_STANDARD) return COLOR_STANDARD;
	if(type == NODE_TYPE_BACHMANN_BUNDLE) return COLOR_BACHMANNS_BUNDLE;
	if(type == NODE_TYPE_APPENDAGE) return COLOR_APPENDAGE;
	if(type == NODE_TYPE_SCAR_TISSUE) return COLOR_SCAR_TISSUE;
	if(type == NODE_TYPE_PULMONARY_VEINS) return COLOR_PULMONARY_VEINS;
	if(type == NODE_TYPE_MITRAL_VALVE) return COLOR_MITRAL_VALVE;
	return COLOR_STANDARD;
}

/*
 Sets a single muscle type and color based on its endpoint node types.
 Returns false if the muscle references an invalid or unknown node type.
*/
bool setMuscleTypeAndColor(int muscleId)
{
	if(muscleId < 0 || muscleId >= NumberOfMuscles)
	{
		return false;
	}

	int a = Muscle[muscleId].nodeA;
	int b = Muscle[muscleId].nodeB;

	if(a < 0 || b < 0 || a >= NumberOfNodes || b >= NumberOfNodes) //check if connecting nodes are valid
	{
		return false; //if invalid return false
	}

	int typeA = Node[a].type;
	int typeB = Node[b].type;
	int priorityA = getTypePriority(typeA);
	int priorityB = getTypePriority(typeB);

	if(priorityA < 0 || priorityB < 0)
	{
		printf("\n\n Unknown node type found while setting muscle %d (nodeA type=%d, nodeB type=%d).", muscleId, typeA, typeB);
		return false;
	}

	//figures out what type the muscle should be based on the types of its endpoint nodes and the priority of those types.
	// If the node types are the same, the muscle gets that type. If they differ, the muscle gets the type of the higher priority node.
	int resolvedType = (typeA == typeB) ? typeA : ((priorityA >= priorityB) ? typeA : typeB);
	Muscle[muscleId].type = resolvedType;
	Muscle[muscleId].color = getColorFromType(resolvedType);

	return true;
}

/*
 This function sets each muscle type from its two endpoint node types.
 Rules:
 1. If nodeA and nodeB have the same type, muscle gets that type.
 2. If they differ, choose by explicit priority (higher wins).
*/
bool setMuscleTypes()
{
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		if(!setMuscleTypeAndColor(i))
		{
			return false;
		}
	}

	return true;
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
 6: Here we set the muscle contraction strength attributes. 
    The myocyte force per mass ratio is calculated by treating a myocyte as a cylinder. 
    In the for loop we add some small random fluctuations to these values so the simulation can have some stochastic behavior. 
    If you do not want any stochastic behavior simply set MyocyteForcePerMassSTD to zero in the simulationsetup file.
    The strength is also scaled using the scaling read in from the simulationSetup file. The scaling is used so the user
    can adjust the standard muscle attributes to perform as desired in their simulation. A value of 1.0 adds no scaling.
 7: Setting Bachmann's Bundle, coloring the nodes and adjusting the connecting muscle's conduction velocity. 
    
 Note: Muscles do not have mass in the simulation. All the mass is carried in the nodes. Muscles were given mass here to be able to
 generate the node masses and area. We carry the muscle masses forward in the event that we need to generate a muscle ratio in 
 future updates to the program. 
*/
void setRemainingNodeAndMuscleAttributes()
{	

	// 3:
	double dx, dy, dz, d;
	double totalLengthOfAllMuscles = 0.0;
	for(int i = 0; i < NumberOfMuscles; i++)
	{	
		dx = Node[Muscle[i].nodeA].position.x - Node[Muscle[i].nodeB].position.x;
		dy = Node[Muscle[i].nodeA].position.y - Node[Muscle[i].nodeB].position.y;
		dz = Node[Muscle[i].nodeA].position.z - Node[Muscle[i].nodeB].position.z;
		d = sqrt(dx*dx + dy*dy + dz*dz);
		totalLengthOfAllMuscles += d;
	}
		
	// 7:
	int id, id2;
	for(int i = -1; i < NumberOfNodesInBachmannsBundle; i++)
	{	
		if(i == -1)
		{
			id = PulsePointNode;
			Node[id].color.x = BachmannColor.x;
			Node[id].color.y = BachmannColor.y;
			Node[id].color.z = BachmannColor.z;
		}
		else
		{
			id = BachmannsBundle[i];
			Node[id].color.x = BachmannColor.x;
			Node[id].color.y = BachmannColor.y;
			Node[id].color.z = BachmannColor.z;
		}
		
		for(int k = 0; k < MUSCLES_PER_NODE; k++)
		{
			id2 = Node[id].muscle[k];
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
						}
					}
				
				}
			}
		}
	}
	
	printf("\n All node and muscle attributes have been set.\n");
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

              
		Simulation.ViewFlag = 1;
		Simulation.DrawNodesFlag = 0;
		Simulation.DrawFrontHalfFlag = 0;
		Simulation.isInMouseFunctionMode = false;
		Simulation.mouseMode = MOUSE_MODE_OFF;
		Simulation.guiCollapsed = false;
		
		if(!isBinaryInput)
		{
			setView(6); //Set deafult view only if not loading from a binary snapshot.
		}
	}

	//TODO: It would be nice to rename this variable (HitMultipler) to something like MouseSelectionSensitivity in the future for clarity.	
	HitMultiplier = 0.1;
	MouseZ = RadiusOfLeftAtrium;
	MouseX = 0.0;
	MouseY = 0.0;
	ScrollSpeedToggle = 1;
	ScrollSpeed = 0.5;
	MouseWheelPos = 0;
	RecenterCount = 0;
	RecenterRate = 10;
}

/*
 Checks to see if an error occurred in a CUDA call and returns the file name and line number where the error occurred.
*/
void cudaErrorCheck(const char *file, int line)
{
	cudaError_t  error;
	error = cudaGetLastError();

	if(error != cudaSuccess)
	{
		printf("\n CUDA ERROR: message = %s, File = %s, Line = %d\n", cudaGetErrorString(error), file, line);
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
}

/*
 Saves node/muscle attributes to one binary file using a simple fwrite layout.
 The file is written to:
 ../NodesMuscles/bin/<NodesMusclesFileName>_<timestamp>.bin

 Binary layout (version 1):
 - version
 - NumberOfNodes
 - NumberOfMuscles
 - PulsePointNode
 - UpNode
 - FrontNode
 - per node: type(int), position(float4), muscle[MUSCLES_PER_NODE](int), color(float4)
 - per muscle: type(int), nodeA(int), nodeB(int), naturalLength(float), color(float4)
*/
void saveBinary()
{
	FILE *binaryFile;
	char fileName[512];

	// We cannot save unless both arrays are loaded in memory.
	if(Node == NULL || Muscle == NULL)
	{
		printf("\n\n Node/Muscle data is not loaded.\n");
		snprintf(BinarySaveStatusMessage, sizeof(BinarySaveStatusMessage), "Binary save failed: Node/Muscle data is not loaded.");
		return;
	}

	// Require a base file name so we can generate a proper output path.
	if(NodesMusclesFileName[0] == '\0')
	{
		printf("\n\n NodesMusclesFileName is empty.\n");
		snprintf(BinarySaveStatusMessage, sizeof(BinarySaveStatusMessage), "Binary save failed: NodesMusclesFileName is empty.");
		return;
	}

	// Ensure muscle types reflect the current node typing before export.
	if(!setMuscleTypes())
	{
		snprintf(BinarySaveStatusMessage, sizeof(BinarySaveStatusMessage), "Binary save failed: Unknown node type in setMuscleTypes().");
		return;
	}

	// Build output file path with timestamp suffix to avoid name collisions.
	std::string timeStamp = getTimeStamp();
	strcpy(fileName, "../NodesMuscles/bin/");
	strcat(fileName, NodesMusclesFileName);
	strcat(fileName, "_");
	strcat(fileName, timeStamp.c_str());
	strcat(fileName, ".bin");

	// Open output file in binary write mode.
	binaryFile = fopen(fileName, "wb");
	if(binaryFile == NULL)
	{
		printf("\n\n Could not create binary file %s.\n", fileName);
		snprintf(BinarySaveStatusMessage, sizeof(BinarySaveStatusMessage), "Binary save failed: Could not create output file.");
		return;
	}

	// Header for basic validation by future readers.
	int version = 1; // Keep this aligned with the binary readers in model/config.
	fwrite(&version, sizeof(int), 1, binaryFile);

	// Save counts and required orientation nodes.
	fwrite(&NumberOfNodes, sizeof(int), 1, binaryFile);
	fwrite(&NumberOfMuscles, sizeof(int), 1, binaryFile);
	fwrite(&PulsePointNode, sizeof(int), 1, binaryFile);
	fwrite(&UpNode, sizeof(int), 1, binaryFile);
	fwrite(&FrontNode, sizeof(int), 1, binaryFile);

	// Save nodes.
	for(int i = 0; i < NumberOfNodes; i++)
	{
		// Write node type for section classification.
		fwrite(&Node[i].type, sizeof(int), 1, binaryFile);
		// Write node position used to reconstruct geometry.
		fwrite(&Node[i].position, sizeof(float4), 1, binaryFile);
		// Write node-to-muscle connectivity map.
		fwrite(Node[i].muscle, sizeof(int), MUSCLES_PER_NODE, binaryFile);
		// Write node color so section coloring can be restored later.
		fwrite(&Node[i].color, sizeof(float4), 1, binaryFile);
	}

	// Save muscles information
	for(int i = 0; i < NumberOfMuscles; i++)
	{
		// Recompute rest length from node positions so geometry and mechanics stay in sync.
		float dx = Node[Muscle[i].nodeA].position.x - Node[Muscle[i].nodeB].position.x;
		float dy = Node[Muscle[i].nodeA].position.y - Node[Muscle[i].nodeB].position.y;
		float dz = Node[Muscle[i].nodeA].position.z - Node[Muscle[i].nodeB].position.z;
		float naturalLength = sqrtf(dx*dx + dy*dy + dz*dz);

		// Write muscle section type.
		fwrite(&Muscle[i].type, sizeof(int), 1, binaryFile);
		// Write both endpoint node ids.
		fwrite(&Muscle[i].nodeA, sizeof(int), 1, binaryFile);
		fwrite(&Muscle[i].nodeB, sizeof(int), 1, binaryFile);
		// Write natural length used by mechanics.
		fwrite(&naturalLength, sizeof(float), 1, binaryFile);
		// Write muscle color so section coloring can be restored later.
		fwrite(&Muscle[i].color, sizeof(float4), 1, binaryFile);
	}

	// Close file handle before reporting success.
	fclose(binaryFile);
	printf("\n Binary file saved: %s\n", fileName);
	const char* statusPrefix = "Binary saved: ";
	size_t prefixLen = strlen(statusPrefix);
	size_t available = (sizeof(BinarySaveStatusMessage) > prefixLen + 1)
		? (sizeof(BinarySaveStatusMessage) - prefixLen - 1)
		: 0;
	memcpy(BinarySaveStatusMessage, statusPrefix, prefixLen);
	if(available > 0)
	{
		strncpy(BinarySaveStatusMessage + prefixLen, fileName, available);
		BinarySaveStatusMessage[prefixLen + available] = '\0';
	}
	else
	{
		BinarySaveStatusMessage[sizeof(BinarySaveStatusMessage) - 1] = '\0';
	}
}

#endif // SETNODESNMUSCLES_H