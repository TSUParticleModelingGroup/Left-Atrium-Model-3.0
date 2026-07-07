/*
 This file contains all the CUDA and CUDA related function. 
 
 They are listed below in the order they appear.
 
 __device__ void turnOnNodeMusclesGPU(int, int, int, muscleAttributesStructure *, nodeAttributesStructure *);
 __global__ void getForces(muscleAttributesStructure *, nodeAttributesStructure *, float, int, float4, float, float, float, float);
 __global__ void updateNodes(nodeAttributesStructure *, int, int, muscleAttributesStructure *, float, float, float, bool);
 __global__ void updateMuscles(muscleAttributesStructure *, nodeAttributesStructure *, int, int, float, float4, float4, float4, float4);
 __global__ void recenter(nodeAttributesStructure *, int, float, float4);
 void cudaErrorCheck(const char *, int);
 void copyNodesMusclesToGPU();
 void copyNodesMusclesFromGPU();
 void copyNodesFromGPU();
 void copyNodesToGPU();
*/

#include "cudaFunctions.h"



/*
 This CUDA function tries to turn on every muscle that is connected to a node.
 It loops through all the muscle connected to the node with index = nodeToTurnOn.
 1: Checks to see if it really is a muscle (muscle number not equal to -1).
    and Checks to see if the muscle is on or off. If it is off it is ready to turn on. 
    There is no need to see if a muscle is dead here because if it is dead turning it on will do nothing.
    Then it: 
 	a. Sets which node turned it on so it can send the conduction signal in the proper direction. 
 	b. Sets the muscle to on.
 	c. Sets the muscle's timer to 0.0.
*/
__device__ void turnOnNodeMusclesGPU(int nodeToTurnOn, int numberOfNodes, int musclesPerNode, muscleAttributesStructure *muscle, nodeAttributesStructure *node)
{
	int muscleNumber;
	
	for(int j = 0; j < musclesPerNode; j++) // Looping through all muscle connected to this node.
	{
		muscleNumber = node[nodeToTurnOn].muscle[j];
		
		// 1: Is this a legit muscle and is it ready to turn on.
		if((muscleNumber != -1) && (!muscle[muscleNumber].isOn))
		{
			muscle[muscleNumber].apNode = nodeToTurnOn;  //a: This is the node where the AP wave will now start moving away from.
			muscle[muscleNumber].isOn = true; //b: Set to on.
			muscle[muscleNumber].timer = 0.0; //c: Set timer.
		}
	}
}

/*
 This CUDA function calculates all of the position-forces on a node. Most of these forces are due 
 to the muscles connected to the nodes, but one is a central outward pushing force that represents 
 the pressure from the blood in the LA. 
 
 The only other force on a node is its drag force. This is a velocity-based force and is calculated 
 in the updateNodes function. 
 
 The function's parallel structure is node-based (GridNodes, BlockNodes).
 The different type forces are explained here and numbered so the reader can see where they are applied
 below in the function.
 
 1. Central push back force:
 	If you are using a line or circle nodes and muscles file pressure does not make much sense but
 	this force is still useful. In a lines simulation it helps straighten the line out after a beat.
 	In a circle simulation it helps return the nodes out to a circle after a beat.
 	For the 3-D shell simulations we use force = pressure*area. The area of a node is calculated in the 
 	setMuscleAttributesAndNodeMasses() function. The pressure is is a linear function that starts from
 	DiastolicPressureLA when the node is a full radiusOfLeftAtrium and increases to SystolicPressureLA
 	when a node is at its contracted length of muscleCompressionStopFraction*radiusOfLeftAtrium. We also use 
 	a multiplier so the user can adjust this force to fit their needs.
 
 This next set of functions gets the forces on a node caused by a muscles at all times, not just when it
 is under contraction. It pulls back when a muscle is stretched past its natural length, pushes back when a 
 muscle is compressed past it maximal compression length, and helps restore a muscle to its natural length 
 when it is between these two values.
 
 2. Muscle is too short force: 
 	If a muscle starts to become shorter than compressionStopFraction*naturalLength it will start to push
 	back. To keep this from being an abrupt change we transition into it. This transition starts at 10% of 
 	the amount a muscle can contract with equals [0.1*(1 - compressionStopFraction)*naturalLength].
 	Note: We used the amount a muscle can contract not the compressionStopFraction because using the 
 	compressionStopFraction might make a case where the transition zone reaches past the natural length in
 	the subsequent force functions.
 	
 	This starts at the relaxed strength. The relaxed force is always on to help return a muscle to its natural 
 	length, as stated above. It cancels out the contraction strength by the time it hits the contraction stop length. 
	If d which equals the actual muscle length at this moment in time, gets shorter than the contraction stop length 
	the push back force just keeps increasing. This is accomplished in the linear function below 2..
 	
 3. Restoration force	
 	In this region the muscle is neither too short or too long. In this region we add a small push back force to help
 	the muscle return to its natural length. This is a constant force force with strength equal to the relaxedStrength 
 	which is a fraction of the contractionStrength. This function and the pressure restore the AL to it relaxed shape.
 	
 4. Approaching natural length transition force
 	As the muscle approaches its natural length we linearly transition it into having a force of zero when it reaches 
 	its natural length.

 5. Muscle too long force
	If for some reason a muscle is stretched past its natural length this function will linearly pull it back to its 
	natural length. It should be a good bit stronger than the relaxedStrength. We are not putting in a distance where 
	the muscle actually breaks. If it gets stretched that far we have bigger problems we need to address. 
	We transition into this taking it from zero to the contractionStrength in one transitionLength. Past one transitionLength 
	it will just keep increasing. We use contractionStrength and transitionLength here because they are already scaled 
	to work on this muscle.

 6. sine squared contraction force
 	This contraction force transitions from zero to full strength as time goes from zero to half the refractory period. 
 	Then goes from full strength to zero as time progresses on to the full refractory period. Here we use a sine squared 
 	function to achieve this because it smoothly transition in and out of the contraction.
 	
 7. The user can completely turn off the contraction function if they only want to watch the electrical activity across the LA 
    by setting the contractionType to zero in the simulationSetUp file.
 
*/
__global__ void getForces(muscleAttributesStructure *muscle, nodeAttributesStructure *node, float dt, int numberOfNodes, float4 centerOfSimulation, float muscleCompressionStopFraction, float radiusOfLeftAtrium, float diastolicPressureLA, float systolicPressureLA)
{
	float dx, dy, dz, d;
	int muscleNumber;
	int opposingNodeNumber;
	float x1,x2,y1,y2,m;
	float force;
	float timer;
	float totalDuration;
	float contractionStrength;
	float relaxedStrength;
	float naturalLength;
	float compressionStopFraction;
	float contractedLength;
	float transitionLength;
	
	int i = threadIdx.x + blockDim.x*blockIdx.x; // This is the node number we will be working on.
	
	if(i < numberOfNodes) // checking to see if this node is in range.
	{
		// Zeroing out the forces on this node so we can start summing them.
		node[i].force.x   = 0.0;
		node[i].force.y   = 0.0;
		node[i].force.z   = 0.0;
		
		// 1: Central push back force
		dx = node[i].position.x - centerOfSimulation.x;
		dy = node[i].position.y - centerOfSimulation.y;
		dz = node[i].position.z - centerOfSimulation.z;
		d  = sqrt(dx*dx + dy*dy + dz*dz);
		if(ASUMEZERO < d) // To keep from getting numeric overflow just jump over this if d is too small.
		{
			float r2 = muscleCompressionStopFraction*radiusOfLeftAtrium;
			m = (systolicPressureLA - diastolicPressureLA)/(r2 - radiusOfLeftAtrium);
			float bp = m*d + diastolicPressureLA - m*radiusOfLeftAtrium;
			force  = bp*node[i].area;
			node[i].force.x  += force*dx/d;
			node[i].force.y  += force*dy/d;
			node[i].force.z  += force*dz/d;
		}
		else
		{
			printf("\n TSU Error: Node %d has gotten really close to the center of the LA. Take a look at this!\n", i);
		}
		
		for(int j = 0; j < MUSCLES_PER_NODE; j++) // Going through every muscle that is connected to the ith node.
		{
			muscleNumber = node[i].muscle[j];
			// Checking to see if this is a valid muscle.
			if(muscleNumber != -1) 
			{
				timer = muscle[muscleNumber].timer;
				totalDuration = muscle[muscleNumber].refractoryPeriod;
				
				contractionStrength = muscle[muscleNumber].contractionStrength;
				relaxedStrength = muscle[muscleNumber].relaxedStrength;
				
				naturalLength = muscle[muscleNumber].naturalLength;
				compressionStopFraction = muscle[muscleNumber].compressionStopFraction;
				contractedLength = naturalLength*compressionStopFraction;
				transitionLength = 0.1*(naturalLength - contractedLength);
				
				// Every muscle is connected to two nodes A and B. We know it is connected to the 
				// ith node. Now we need to find the node at the other end of the muscle.
				opposingNodeNumber = muscle[muscleNumber].nodeA;
				// If the node number is yourself you must have the wrong end.
				if(opposingNodeNumber == i) opposingNodeNumber = muscle[muscleNumber].nodeB; 
			
				dx = node[opposingNodeNumber].position.x - node[i].position.x;
				dy = node[opposingNodeNumber].position.y - node[i].position.y;
				dz = node[opposingNodeNumber].position.z - node[i].position.z;
				d  = sqrt(dx*dx + dy*dy + dz*dz);
				if(d < ASUMEZERO) // Grabbing numeric overflow before it happens.
				{
					printf("\n TSU Error: In generalMuscleForces d is very small between opposingNodeNumbers %d and %d the separation is %f. Take a look at this!\n", i, opposingNodeNumber, d);
				}
				
				// The following (2-5) force functions are always on
				// even if the muscle is disabled. This just keeps the muscle 
				// at its natural length.
				if(d < (contractedLength + transitionLength))
				{
					// 2: Muscle is getting too short force
					x1 = contractedLength;
					x2 = x1 + transitionLength;
					y1 = -contractionStrength;
					y2 = -relaxedStrength;
					m = (y2 - y1)/(x2 - x1);
					force = m*(d - x1) + y1;
				}
				else if(d < naturalLength - transitionLength)
				{
					// 3: Restoration force
					force = -relaxedStrength;
				}
				else if(d < naturalLength)
				{
					// 4: Approaching natural length transition force
					m = relaxedStrength/transitionLength;
					force = m*(d - naturalLength);
				}
				else
				{
					// 5: Muscle too long force
					m = contractionStrength/transitionLength;
					force = m*(d - naturalLength - transitionLength) + contractionStrength;
				}
				
				node[i].force.x  += force*dx/d;
				node[i].force.y  += force*dy/d;
				node[i].force.z  += force*dz/d;
			
				// Checking to see if the muscle is on and has not been disabled.
				if(muscle[muscleNumber].isOn && muscle[muscleNumber].isEnabled)
				{	
					// 6: sine squared contraction force
				 	float temp = sin(timer*PI/(totalDuration));
					force = contractionStrength*temp*temp;
					node[i].force.x += force*dx/d;
					node[i].force.y += force*dy/d;
					node[i].force.z += force*dz/d;
				}
				
			}
		}
	}
}

/*
 This CUDA function first moves the nodes then checks to see if the node is a beat node, if it is, it updates its time 
 and if its time is past the beat period it sends out a signal then zeros out its timer to start a new period.
 
 We also add some drag to the system to remove energy buildup.
*/
__global__ void updateNodes(nodeAttributesStructure *node, int numberOfNodes, int musclesPerNode, muscleAttributesStructure *muscle, float drag, float dt, float time, bool contractionIsOn)
{
	int i = threadIdx.x + blockDim.x*blockIdx.x;
	
	if(i < numberOfNodes)
	{
		if(contractionIsOn)
		{	
			// Moving the nodes forward in time with the leap-frog formulas. 
			if(time == 0.0)
			{
				node[i].velocity.x += (node[i].force.x/node[i].mass - drag*node[i].velocity.x)*0.5*dt;
				node[i].velocity.y += (node[i].force.y/node[i].mass - drag*node[i].velocity.y)*0.5*dt;
				node[i].velocity.z += (node[i].force.z/node[i].mass - drag*node[i].velocity.z)*0.5*dt;
			}
			else
			{
				node[i].velocity.x += (node[i].force.x/node[i].mass - drag*node[i].velocity.x)*dt;
				node[i].velocity.y += (node[i].force.y/node[i].mass - drag*node[i].velocity.y)*dt;
				node[i].velocity.z += (node[i].force.z/node[i].mass - drag*node[i].velocity.z)*dt;
			}
			
			node[i].position.x += node[i].velocity.x*dt;
			node[i].position.y += node[i].velocity.y*dt;
			node[i].position.z += node[i].velocity.z*dt;
		}
		
		if(!node[i].isAblated) // If node is not ablated do some work on it.
		{
		
			if(node[i].isBeatNode)
			{
				if(node[i].beatPeriod < node[i].beatTimer) // If the time is past its period set it to fire and reset it internal clock.
				{	
					node[i].isFiring = true;		
					node[i].beatTimer = 0.0; 
				}
				else
				{
					node[i].beatTimer += dt;
				}
			}
			
			// Turning on the muscle to any node that is ready to fire. Then setting fire to false so it will not fire again until it is ready.
			if(node[i].isFiring)
			{
				turnOnNodeMusclesGPU(i, numberOfNodes, musclesPerNode, muscle, node);
				node[i].isFiring = false;
			}
		}
	}	
}

/*
 This function triggers the next node when its signal reaches the end of the muscle.
 Then it colors the muscle depending on where the muscle is in its cycle.
 If a muscle reaches the end of its cycle it is turned off, its timer is set to zero,
 and its transmittion direction set to undetermined by setting apNode to -1. (do you mean transition or transmission-kyla ? Second this -Mason)
*/
__global__ void updateMuscles(muscleAttributesStructure *muscle, nodeAttributesStructure *node, int numberOfMuscles, int numberOfNodes, float dt, float4 readyColor, float4 depolarizingColor, float4 repolarizingColor, float4 relativeRepolarizingColor)
{
	int i = threadIdx.x + blockDim.x*blockIdx.x;
	int nodeId;
	
	if(i < numberOfMuscles)
	{
		if(muscle[i].isOn && muscle[i].isEnabled)
		{
			// Turning on the next node when the conduction front reaches it. This is at a certain floating point time this is why we used the +-dt
			// You can't just turn it on when the timer is greater than the conductionDuration because the timer is not reset here
			// and this would make this call happen every time step past conductionDuration until it was reset.
			if((muscle[i].conductionDuration - dt < muscle[i].timer) && (muscle[i].timer < muscle[i].conductionDuration + dt))
			{
				// Making the AP wave move forward through the muscle.
				if(muscle[i].apNode == muscle[i].nodeA)
				{
					nodeId = muscle[i].nodeB;
				}
				else
				{
					nodeId = muscle[i].nodeA;
				}
				
				if(!node[nodeId].isBeatNode)
				{
					node[nodeId].isFiring = true;
				}
				else
				{
					// If you want to do something with a beat node when it is hit by a signal, 
					// like reset its internal clock, do it here.
					// Currently we are simply ignoring the signal.
				}
			}
		
			float refractoryPeriod = muscle[i].refractoryPeriod;
			float absoluteRefractoryPeriod = refractoryPeriod*muscle[i].absoluteRefractoryPeriodFraction;
			//float relativeRefractoryPeriod = refractoryPeriod - absoluteRefractoryPeriod;
			
			if(muscle[i].timer < 0.5*refractoryPeriod)
			{
				// Set color and update time.
				muscle[i].color.x = depolarizingColor.x; 
				muscle[i].color.y = depolarizingColor.y;
				muscle[i].color.z = depolarizingColor.z;
				muscle[i].timer += dt;
			}
			else if(muscle[i].timer < absoluteRefractoryPeriod)
			{ 
				// Set color and update time.
				muscle[i].color.x = repolarizingColor.x;
				muscle[i].color.y = repolarizingColor.y;
				muscle[i].color.z = repolarizingColor.z;
				muscle[i].timer += dt;
			}
			else if(muscle[i].timer < refractoryPeriod)
			{ 
				// If you want to do something different in the relative refractory period do it here.
				// Set color and update time.
				muscle[i].color.x = relativeRepolarizingColor.x;
				muscle[i].color.y = relativeRepolarizingColor.y;
				muscle[i].color.z = relativeRepolarizingColor.z;
				muscle[i].timer += dt;
			}
			else
			{
				// Set color and turning the muscle off, reset timer, and apNode to unknown.
				muscle[i].color.x = readyColor.x;
				muscle[i].color.y = readyColor.y;
				muscle[i].color.z = readyColor.z;
				muscle[i].color.w = 1.0;
				
				muscle[i].isOn = false;
				muscle[i].timer = 0.0;
				muscle[i].apNode = -1;
			}	
		}
	}	
}

/*
 Moves the center of mass of the nodes to the center of the simulation. The nodes tend to wander because the model and
 the forces are not completely symmetric. This function just moves it back to the center of the simulation.
 We are doing this on one block so we do not have to jump out to sync the blocks then move the nodes to the center.
 Note: The block size here needs to be a power of 2 for the reduction to work. We check for this in the setupCudaEnvironment()
 function in the SVT.cu file.
*/
__global__ void recenter(nodeAttributesStructure *node, int numberOfNodes, float massOfLA, float4 centerOfSimulation)
{
	int id, n, nodeId;
	
	// This needs to be a power of two or the code will not work!!!
	__shared__ float4 myPart[BLOCKCENTEROFMASS];
	
	id = threadIdx.x;
	
	myPart[id].x = 0.0;
	myPart[id].y = 0.0;
	myPart[id].z = 0.0;
	myPart[id].w = 0.0;
	
	// Finding the number of strides needed to go through all of the nodes using only one block.
	int stop = (numberOfNodes - 1)/blockDim.x + 1;
	
	// Summing all of the node masses*distance and total node masses into the single block we are using.
	for(int i = 0; i < stop; i++)
	{
		nodeId = threadIdx.x + i*blockDim.x;
		// Checking to make sure we are not going past the number of nodes.
		// This will protect the sum if the number of nodes does not equally divide by the size of the block.
		if(nodeId < numberOfNodes)
		{
			myPart[id].x += node[nodeId].position.x*node[nodeId].mass;
			myPart[id].y += node[nodeId].position.y*node[nodeId].mass;
			myPart[id].z += node[nodeId].position.z*node[nodeId].mass;
		}
	}
	__syncthreads();
	
	// Doing the final reduction on the value we have accumulated on the block. 
	// This will all be stored in node zero when this while loop is done.
	// Note: This section of code only works if block size is a power of 2.
	n = blockDim.x;
	while(1 < n)
	{
		n /= 2;
		if(id < n)
		{
			myPart[id].x += myPart[id + n].x;
			myPart[id].y += myPart[id + n].y;
			myPart[id].z += myPart[id + n].z;
		}
		__syncthreads();
	}
	__syncthreads();
	
	// Dividing by the total mass will now give us the center of mass of all the nodes.
	if(id == 0)
	{
		myPart[0].x /= massOfLA;
		myPart[0].y /= massOfLA;
		myPart[0].z /= massOfLA;
	}
	__syncthreads();
	
	// Moving the nodes so that the nodes' center of mass will be at the center of the simulation.
	for(int i = 0; i < stop; i++)
	{
		nodeId = threadIdx.x + i*blockDim.x;
		if(nodeId < numberOfNodes)
		{
			node[nodeId].position.x -= myPart[0].x - centerOfSimulation.x;
			node[nodeId].position.y -= myPart[0].y - centerOfSimulation.y;
			node[nodeId].position.z -= myPart[0].z - centerOfSimulation.z;
		}	
	}
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
 Copies nodes and muscle attributes up to the GPU.
*/
void copyNodesMusclesToGPU()
{
    cudaMemcpyAsync(MuscleGPU, Muscle, NumberOfMuscles*sizeof(muscleAttributesStructure), cudaMemcpyHostToDevice, MemoryStream);
    cudaErrorCheck(__FILE__, __LINE__);
    
    cudaMemcpyAsync(NodeGPU, Node, NumberOfNodes*sizeof(nodeAttributesStructure), cudaMemcpyHostToDevice, MemoryStream);
    cudaErrorCheck(__FILE__, __LINE__);
    
    // Synchronize memory stream to ensure transfer is complete
    cudaStreamSynchronize(MemoryStream);
}

/*
 * Copies nodes and muscle attributes down from the GPU.
 */
void copyNodesMusclesFromGPU()
{
    cudaMemcpyAsync(Muscle, MuscleGPU, NumberOfMuscles*sizeof(muscleAttributesStructure), cudaMemcpyDeviceToHost, MemoryStream);
    cudaErrorCheck(__FILE__, __LINE__);
    
    cudaMemcpyAsync(Node, NodeGPU, NumberOfNodes*sizeof(nodeAttributesStructure), cudaMemcpyDeviceToHost, MemoryStream);
    cudaErrorCheck(__FILE__, __LINE__);
    
    // Synchronize memory stream to ensure transfer is complete
    cudaStreamSynchronize(MemoryStream);
}

/*
 * Copies node attributes down from the GPU
 */
void copyNodesFromGPU()
{
    cudaMemcpyAsync(Node, NodeGPU, NumberOfNodes*sizeof(nodeAttributesStructure), cudaMemcpyDeviceToHost, MemoryStream);
    cudaErrorCheck(__FILE__, __LINE__);

	// Synchronize memory stream to ensure transfer is complete
    cudaStreamSynchronize(MemoryStream);
}

/*
 * Copies node attributes up to the GPU
 */
void copyNodesToGPU()
{
    cudaMemcpyAsync(NodeGPU, Node, NumberOfNodes*sizeof(nodeAttributesStructure), cudaMemcpyHostToDevice, MemoryStream);
    cudaErrorCheck(__FILE__, __LINE__);

	// Synchronize memory stream to ensure transfer is complete
    cudaStreamSynchronize(MemoryStream);
}


