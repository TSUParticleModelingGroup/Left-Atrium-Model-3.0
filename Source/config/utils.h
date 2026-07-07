#ifndef UTILS_H
#define UTILS_H

#include "globals.h"
#include "file_io.h"
#include <stdio.h>
#include <string>
#include <iostream>
#include <stdlib.h>
#include <sstream>
#include <math.h>

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

void readBasicSimulationSetupParameters()
{
	ifstream data;
	string name;
	
	data.open("../BasicSimulationSetup");
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

		//TODO: Rework settings file to fix this
		int temp;	
		getline(data,name,'=');
		//data >> Simulation.ContractionisOn;
		data >> temp;

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

void setup()
{	

	// Seeding the random number generator.
	time_t t;
	srand((unsigned) time(&t));

	//create CUDA streams for async memory copy and compute
	cudaStreamCreate(&ComputeStream);
	cudaStreamCreate(&MemoryStream);
	readBasicSimulationSetupParameters();	

	char *extension = strrchr(NodesMusclesFileName, '.');
	bool isBinaryInput = (extension != NULL && strcmp(extension, ".bin") == 0);

	// Config input mode is selected by file extension in NodesMusclesFileName.
	if(isBinaryInput)
	{
		readNodesAndMusclesFromBinaryFile();
		float3 objectCenter;
		if(!findCenterOfObject(&objectCenter, Node, NumberOfNodes)) exit(0);
		if(!findAverageRadiusOfObject(&RadiusOfLeftAtrium, Node, NumberOfNodes)) exit(0);
		setRemainingNodeAndMuscleAttributes();
	}
	else
	{
		readNodesFromFile();	
		float3 objectCenter;
		if(!findCenterOfObject(&objectCenter, Node, NumberOfNodes)) exit(0);
		if(!moveObjectToOrigin(Node, NumberOfNodes)) exit(0);
		if(!findAverageRadiusOfObject(&RadiusOfLeftAtrium, Node, NumberOfNodes)) exit(0);
		//centerNodes();
		checkNodes();
		readPulseUpAndFrontNodesFromFile();
		readBachmannBundleFromFile();
		readMusclesFromFile();
		linkNodesToMuscles();
		if(!setMuscleTypes())
		{
			printf("\n The simulation has been terminated.\n\n");
			exit(0);
		}
		setRemainingNodeAndMuscleAttributes();
	}
	
	// Setting parameters that are not initially read from the node and muscle or previous run file.
	setRemainingParameters();
	
	// Setting up the CUDA parallel structure to be used.
	setupCudaEnvironment();

	// Sending all the info that we have just created to the GPU so it can start crunching numbers.
	//copyNodesMusclesToGPU();
	
	printf("\n\n Have a good simulation.\n\n");
}


/*
 This function is used to clear the print buffer.
*/
void clearStdin()
{
    int c;
    while ((c = getchar()) != '\n' && c != EOF)
    {
        /* discard characters */
    }
}

/*
 This function returns a timestamp in M-D-Y-H.M.S format.
 This is use so each file that is created has a unique name. 
 Note: You cannot create more than one file in a second or you will over write the previous file.
*/
std::string getTimeStamp()
{
	// Want to get a time stamp string representing current date/time, so we have a
	// unique name for each video/screenshot taken.
	time_t t = time(0); 
	struct tm * now = localtime( & t );
	int month = now->tm_mon + 1, day = now->tm_mday, year = now->tm_year, 
				curTimeHour = now->tm_hour, curTimeMin = now->tm_min, curTimeSec = now->tm_sec;

	std::stringstream smonth, sday, syear, stimeHour, stimeMin, stimeSec;

	smonth << month;
	sday << day;
	syear << (year + 1900); // The computer starts counting from the year 1900, so 1900 is year 0. So we fix that.
	stimeHour << curTimeHour;
	stimeMin << curTimeMin;
	stimeSec << curTimeSec;
	std::string timeStamp;

	if (curTimeMin <= 9)
	{
		timeStamp = smonth.str() + "-" + sday.str() + "-" + syear.str() + '_' + stimeHour.str() + ".0" + stimeMin.str() + 
					"." + stimeSec.str();
	}
	else
	{		
		timeStamp = smonth.str() + "-" + sday.str() + '-' + syear.str() + "_" + stimeHour.str() + "." + stimeMin.str() +
					"." + stimeSec.str();
	}

	return timeStamp;
}

#endif // UTILS_H
