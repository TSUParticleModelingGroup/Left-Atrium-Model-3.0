#ifndef VIEW_H
#define VIEW_H

/* This file contains:
 1: All the functions that determine how to orient and view the simulation.
 2: All the functions that draw the actual simulation. 
 3: The functions that print to the linux terminal all the setting of the simulation.
 In short this file holds the functions that present information to the user.

 int findCenterOfObject(nodeAttributesStructure *nodes, int count);
 int moveObjectToOrigin(nodeAttributesStructure *nodes, int count);
 int findAverageRadiusOfObject(nodeAttributesStructure *nodes, int count);
 floa4 findCenterOfMass();
 void renderSphere();
 void sphereVBO();
 void rotateXAxis(float);
 void rotateYAxis(float);
 void rotateZAxis(float);
 void ReferenceView();
 void PAView();
 void APView();
 void setView(int);
 void drawPicture();
*/

/*
This function finds the center of an object by averaging the positions of all the nodes in the object together. 
It returns 1 on success and 0 on failure. The center is returned through the objectCenter pointer parameter.
*/
int findCenterOfObject(float3* objectCenter, nodeAttributesStructure *nodes, int count) 
{
	// Input validation
	if (!objectCenter) 
	{
		printf("findCenterOfObject Error: objectCenter pointer is null.\n");
		return 0; // NULL PTR
	}
	if (!nodes) 
	{
		printf("findCenterOfObject Error: nodes pointer is null.\n");
		return 0; // NULL PTR
	}
	if (count <= 0) 
	{
		printf("findCenterOfObject Error: count must be greater than zero.\n");
		return 0; // Can't divide by zero or have negative nodes
	}

	// Calculate the sum of all node positions
	float3 center = {0,0,0};
	for (int i = 0; i < count; i++)
	{
		center.x += nodes[i].position.x;
		center.y += nodes[i].position.y;
		center.z += nodes[i].position.z;
	}
	
	// Average the sum to find the center and then set it
	// objectCenter->x is the same as (*objectCenter).x
	objectCenter->x =  center.x / count;
	objectCenter->y = center.y / count;	
	objectCenter->z = center.z / count;

	// Debugging print and return on s
	//printf("The center of the object is at (%f, %f, %f)\n", objectCenter->x, objectCenter->y, objectCenter->z);
	return 1;
}

/* 
This function moves an object to the origin by 
	1. Finding the center of the object, which is also how far offset the object is from the origin.
	2. Translating every node in the object by the opposite amount of that offset..
	3. Returns 1 on success and 0 on failure.
	
*/
int moveObjectToOrigin(nodeAttributesStructure *nodes, int count) 
{
	// Input validation
	if (!nodes) 
	{
		printf("moveObjectToOrigin Error: nodes pointer is null.\n");
		return 0; // NULL PTR
	}
	if (count <= 0) 
	{
		printf("moveObjectToOrigin Error: count must be greater than zero.\n");
		return 0; // Can't divide by zero or have negative nodes
	}
	float epsilon = 0.0001f; // A small value to check if the center is already at the origin, so we don't do unnecessary calculations and risk floating point errors.
	float3 center;
	if(!findCenterOfObject(&center, nodes, count)) return 0; // note that findCenterOfObject will print an error if it fails, so we don't need to print another one here.
	if(abs(center.x) < epsilon && abs(center.y) < epsilon && abs(center.z) < epsilon) return 1; // The object is already at the origin, so we can just return success without doing anything.
	
	// Moving the object
	for (int i = 0; i < count; i++)
	{
		nodes[i].position.x -= center.x;
		nodes[i].position.y -= center.y;
		nodes[i].position.z -= center.z;
	}

	//Debugging

	//printf("The object has been moved from (%f, %f, %f) to the origin (0, 0, 0)\n", center.x, center.y, center.z);
	//float3 tempCenter;
	//if(!findCenterOfObject(&tempCenter, nodes, count)) return 0; // Again findCenterOfObject will print an error if it fails, so we don't need to print another one here.	
	//printf("To verify the object was moved correctly, the new center of the object is at (%f, %f, %f)\n", tempCenter.x, tempCenter.y, tempCenter.z);
	
	return 1;
}

/*
This funciton finds the average radius of the object by 
	1. Finding the center of the object.
	2. Finding the distance from each node to the center, which is the radius of that node.
	3. Averaging all those radii together to get the average radius of the object.
	4. Returns 1 on success and 0 on failure
*/
int findAverageRadiusOfObject(double* r, nodeAttributesStructure *nodes, int count) 
{
	// Input validation
	if (!r) 
	{
		printf("findAverageRadiusOfObject Error: objectCenter pointer is null.\n");
		return 0; // NULL PTR
	}
	if (!nodes) 
	{
		printf("findAverageRadiusOfObject Error: nodes pointer is null.\n");
		return 0; // NULL PTR
	}
	if (count <= 0) 
	{
		printf("findAverageRadiusOfObject Error: count must be greater than zero.\n");
		return 0; // Can't divide by zero or have negative nodes
	}

	// Calculate the center of the object
	float3 center = {0,0,0};
	if (!findCenterOfObject(&center, nodes, count)) return 0; // Failed to find center, so can't find radius. Again findCenterOfObject will print its own error if it fails

	// Calculate the distance from each node to the center
	float totalRadius = 0.0f;
	for (int i=0; i < count; i++)
	{
		float dx = nodes[i].position.x - center.x;
		float dy = nodes[i].position.y - center.y;
		float dz = nodes[i].position.z - center.z;
		float distance = sqrtf(dx*dx + dy*dy + dz*dz);
		totalRadius += distance;
	}

	// Average the distances to find the average radius and then set it, and return success
	*r = totalRadius / count;
	//printf("The average radius of the object is %f\n", *r); // The average radius for RealisticLA is around 25.8
	return 1;

}
	
float4 findCenterOfMass()
{
	float4 centerOfMass;
	
	centerOfMass.x = 0.0;
	centerOfMass.y = 0.0;
	centerOfMass.z = 0.0;
	centerOfMass.w = 0.0;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		 centerOfMass.x += Node[i].position.x*Node[i].mass;
		 centerOfMass.y += Node[i].position.y*Node[i].mass;
		 centerOfMass.z += Node[i].position.z*Node[i].mass;
		 centerOfMass.w += Node[i].mass;
	}
	if(centerOfMass.w < 0.00001) // .w holds the mass.
	{
		printf("\n The mass is too small.");
		printf("\n The simulation has been terminated.\n\n");
		exit(0);
	}
	else
	{
		centerOfMass.x /= centerOfMass.w;
		centerOfMass.y /= centerOfMass.w;
		centerOfMass.z /= centerOfMass.w;
	}
	return(centerOfMass);
}

// TODO: The edge rendering scales with the camera position, but the node rendering does not, which can look weird when zooming in and out. 
// It would be nice to make the node rendering also scale with camera position in the future for a more consistent look.
void createSphereVBO(float radius, int slices, int stacks)
{
    std::vector<float> vertices;
    std::vector<unsigned int> indices;
    
    // Generate sphere vertices with positions and normals
	for (int i = 0; i <= stacks; ++i) 
	{
		// Calculate the vertical angle phi (0 to PI, from top to bottom of sphere)
		float phi = PI * i / stacks;
		float sinPhi = sin(phi);
		float cosPhi = cos(phi);
		
		for (int j = 0; j <= slices; ++j) 
		{
			// Calculate the horizontal angle theta (0 to 2PI, around the sphere)
			float theta = 2.0f * PI * j / slices;
			float sinTheta = sin(theta);
			float cosTheta = cos(theta);
			
			// Convert spherical to Cartesian coordinates
			// x = r * sin(phi) * cos(theta)
			// y = r * cos(phi)          // y is up/down axis (poles of the sphere)
			// z = r * sin(phi) * sin(theta)
			float x = radius * sinPhi * cosTheta;
			float y = radius * cosPhi;
			float z = radius * sinPhi * sinTheta;
			
			// For a sphere, normal vectors point outward from center
			// and are simply the normalized position vector (position/radius)
			float nx = sinPhi * cosTheta;  // Same as x/radius
			float ny = cosPhi;             // Same as y/radius
			float nz = sinPhi * sinTheta;  // Same as z/radius
			
			// Store the vertex data in interleaved format:
			// Each vertex has 6 floats - 3 for position (x,y,z) and 3 for normal (nx,ny,nz)
			vertices.push_back(x);
			vertices.push_back(y);
			vertices.push_back(z);
			vertices.push_back(nx);
			vertices.push_back(ny);
			vertices.push_back(nz);
		}
	}
    
	// Generate indices for triangle strips
	// This section creates triangles by connecting the grid of vertices:
	// - First defines index values that point to positions in the vertex array 
	// - Creates two triangles for each grid cell (rectangular patch)
	// - Each triangle is defined by three indices in counter-clockwise order
	for (int i = 0; i < stacks; ++i) 
	{
		for (int j = 0; j < slices; ++j) 
		{
			// Calculate indices for the four corners of the current grid cell
			int first = i * (slices + 1) + j;          // Current vertex
			int second = first + slices + 1;           // Vertex below current
			
			// First triangle: Connect current vertex, vertex below, and vertex to the right
			indices.push_back(first);
			indices.push_back(second);
			indices.push_back(first + 1);
			
			// Second triangle: Connect vertex below, vertex below+right, and vertex to the right
			indices.push_back(second);
			indices.push_back(second + 1);
			indices.push_back(first + 1);
		}
	}

	// Store the total counts for rendering
	NumSphereVertices = vertices.size() / 6; // 6 floats per vertex (pos + normal)
	NumSphereIndices = indices.size();

	// Create and setup OpenGL buffers on the GPU
	// - Generate unique buffer IDs
	// - Bind buffers to set them as active
	// - Copy data from CPU arrays to GPU memory
	glGenBuffers(1, &SphereVBO);  // Generate Vertex Buffer Object for storing positions and normals
	glBindBuffer(GL_ARRAY_BUFFER, SphereVBO);
	glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(float), vertices.data(), GL_STATIC_DRAW);

	// Same process for the index buffer
	glGenBuffers(1, &SphereIBO);  // Generate Index Buffer Object for storing triangle connections
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, SphereIBO);
	glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.size() * sizeof(unsigned int), indices.data(), GL_STATIC_DRAW);

	// Unbind buffers to prevent accidental modification
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
}

void renderSphereVBO() 
{
    // Bind the VBO and IBO
    glBindBuffer(GL_ARRAY_BUFFER, SphereVBO);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, SphereIBO);
    
    // Enable vertex and normal arrays
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    
    // Set up pointers to vertex and normal data
    glVertexPointer(3, GL_FLOAT, 6 * sizeof(float), 0);
    glNormalPointer(GL_FLOAT, 6 * sizeof(float), (void*)(3 * sizeof(float)));
    
    // Draw the sphere
    glDrawElements(GL_TRIANGLES, NumSphereIndices, GL_UNSIGNED_INT, 0);
    
    // Disable arrays
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    
    // Unbind buffers
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
}


// Add this to a utility file, only used for the mouse selection since it's just 1 object
void renderSphere(float radius, int slices, int stacks) 
{
    // Sphere geometry parameters
    float x, y, z, alpha, beta; // Storage for coordinates and angles
    float sliceStep = 2.0f * PI / slices;
    float stackStep = PI / stacks;

    for (int i = 0; i < stacks; ++i) {
        alpha = i * stackStep;
        beta = alpha + stackStep;

        glBegin(GL_TRIANGLE_STRIP);
        for (int j = 0; j <= slices; ++j) {
            float theta = (j == slices) ? 0.0f : j * sliceStep;

            // Vertex 1
            x = -sin(alpha) * cos(theta);
            y = cos(alpha);
            z = sin(alpha) * sin(theta);
            glNormal3f(x, y, z);
            glVertex3f(x * radius, y * radius, z * radius);

            // Vertex 2
            x = -sin(beta) * cos(theta);
            y = cos(beta);
            z = sin(beta) * sin(theta);
            glNormal3f(x, y, z);
            glVertex3f(x * radius, y * radius, z * radius);
        }
        glEnd();
    }
}



/*
 This function sets your view to frustum.This is the view the your eyes actually see. Where train tracks pull in 
 towards each other as they move off in the distance. It is how we see but can cause problems when using the mouse
 which lives in 2D to locate an object that lives in 3D.
*/
void frustumView()
{
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glFrustum(-0.2, 0.2, -0.2, 0.2, Near, Far);
	glMatrixMode(GL_MODELVIEW);
	Simulation.ViewFlag = 1;
	drawPicture();
}


/*
 This function centers the LA and resets the center of view to (0, 0, 0).
 It is called periodically in a running simulation to center the LA, because the LA is not symmetrical 
 and will wander off over time. It is also use to center the LA before all the views are set.
*/
void centerObject()
{
	float4 centerOfMass = findCenterOfMass();
	for(int i = 0; i < NumberOfNodes; i++)
	{
		Node[i].position.x -= centerOfMass.x;
		Node[i].position.y -= centerOfMass.y;
		Node[i].position.z -= centerOfMass.z;
		
		//Node[i].velocity.x = 0.0;
		//Node[i].velocity.y = 0.0;
		//Node[i].velocity.z = 0.0;
	}
	CenterOfSimulation.x = 0.0;
	CenterOfSimulation.y = 0.0;
	CenterOfSimulation.z = 0.0;
}

/*
 This function rotates the view around the x-axis.
*/
void rotateXAxis(float angle)
{
	float temp;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		temp = cos(angle)*Node[i].position.y - sin(angle)*Node[i].position.z;
		Node[i].position.z  = sin(angle)*Node[i].position.y + cos(angle)*Node[i].position.z;
		Node[i].position.y  = temp;
	}
	AngleOfSimulation.x += angle;
}

/*
 This function rotates the view around the y-axis.
*/
void rotateYAxis(float angle)
{
	float temp;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		temp =  cos(-angle)*Node[i].position.x + sin(-angle)*Node[i].position.z;
		Node[i].position.z  = -sin(-angle)*Node[i].position.x + cos(-angle)*Node[i].position.z;
		Node[i].position.x  = temp;
	}
	AngleOfSimulation.y += angle;
}

/*
 This function rotates the view around the z-axis.
*/
void rotateZAxis(float angle)
{
	float temp;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		temp = cos(angle)*Node[i].position.x - sin(angle)*Node[i].position.y;
		Node[i].position.y  = sin(angle)*Node[i].position.x + cos(angle)*Node[i].position.y;
		Node[i].position.x  = temp;
	}
	AngleOfSimulation.z += angle;
}

/*
 This function puts the viewer in the reference view. The reference view is looking straight at the four
 pulmonary veins with a vein in each of the four quadrants of the x-y plane as symmetric as you can make 
 it with the mitral valve down. We base all the other views off of this view.
*/
void ReferenceView()
{	
	float angle, temp;
	
	centerObject();
		
	// Rotating until the up Node is on x-y plane above or below the positive x-axis.
	angle = atan(Node[UpNode].position.z/Node[UpNode].position.x);
	if(Node[UpNode].position.x < 0.0) angle -= PI;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		temp = cos(angle)*Node[i].position.x + sin(angle)*Node[i].position.z;
		Node[i].position.z  = -sin(angle)*Node[i].position.x + cos(angle)*Node[i].position.z;
		Node[i].position.x  = temp;
	}
	AngleOfSimulation.y += angle;
	
	// Rotating until up Node is on the positive y axis.
	angle = PI/2.0 - atan(Node[UpNode].position.y/Node[UpNode].position.x);
	for(int i = 0; i < NumberOfNodes; i++)
	{
		temp = cos(angle)*Node[i].position.x - sin(angle)*Node[i].position.y;
		Node[i].position.y  = sin(angle)*Node[i].position.x + cos(angle)*Node[i].position.y;
		Node[i].position.x  = temp;
	}
	AngleOfSimulation.z += angle;
	
	// Rotating until front Node is on the positive z axis.
	angle = atan(Node[FrontNode].position.z/Node[FrontNode].position.x) - PI/2.0;
	if(Node[FrontNode].position.x < 0.0) angle -= PI;
	for(int i = 0; i < NumberOfNodes; i++)
	{
		temp = cos(angle)*Node[i].position.x + sin(angle)*Node[i].position.z;
		Node[i].position.z  = -sin(angle)*Node[i].position.x + cos(angle)*Node[i].position.z;
		Node[i].position.x  = temp;
	}
	AngleOfSimulation.y += angle;
}

/*
 This function puts the LA in the PA view.
 The heart does not set in the chest at a straight on angle. Hence we need to adjust our 
 reference view to what is actually seen in a back view looking through the chest.
*/
void PAView()
{  
	float angle;
	
	ReferenceView();
	
	angle = PI/6.0; // Rotate 30 degrees counterclockwise on the y-axis 
	rotateYAxis(angle);

	angle = PI/6.0; // Rotate 30 degrees counterclockwise on the z-axis
	rotateZAxis(angle);
}

/*
 This function puts the LA in the AP view.
 To get the AP view we just rotate the PA view 180 degrees on the y-axis
*/
void APView()
{ 
	float angle;
	
	PAView();
	angle = PI; // Rotate 180 degrees counterclockwise on the y-axis 
	rotateYAxis(angle);
}

/*
 This function sets all the views based off of the reference view and the AP view.
*/
void setView(int view)
{
    if(view == 6)
    {
        ReferenceView();
        strcpy(ViewName, "Ref");
    }
    else if(view == 4)
    {
        PAView();
        strcpy(ViewName, "PA");
    }
    else if(view == 2)
    {
        APView();
        strcpy(ViewName, "AP");
    }
    else if(view == 3)
    {
        APView();
        rotateYAxis(-PI/6.0);
        strcpy(ViewName, "RAO");
    }
    else if(view == 1)
    {
        APView();
        rotateYAxis(PI/3.0);
        strcpy(ViewName, "LAO");
    }
    else if(view == 7)
    {
        APView();
        rotateYAxis(PI/2.0);
        strcpy(ViewName, "LL");
    }
    else if(view == 9)
    {
        APView();
        rotateYAxis(-PI/2.0);
        strcpy(ViewName, "RL");
    }
    else if(view == 8)
    {
        APView();
        rotateXAxis(PI/2.0);
        strcpy(ViewName, "SUP");
    }
    else if(view == 5)
    {
        APView();
        rotateXAxis(-PI/2.0);
        strcpy(ViewName, "INF");
    }
    else
    {
        printf("\n Undefined view reverting back to Ref view.");
    }
}

/*
 This function draws the LA to the screen. It also saves movie frames if a movie is being recorded.
*/
void drawPicture()
{
	//int nodeNumber;
	int muscleNumber;
	int k;
	glClear(GL_COLOR_BUFFER_BIT);
	glClear(GL_DEPTH_BUFFER_BIT);
	
	//if(!Simulation.isPaused) glColor3d(0.0,1.0,0.0); // Green is running
	//else glColor3d(1.0,0.0,0.0); // Red is paused	
	glColor3d(Node[PulsePointNode].color.x, Node[PulsePointNode].color.y, Node[PulsePointNode].color.z);
	glPushMatrix();
	glTranslatef(Node[PulsePointNode].position.x, Node[PulsePointNode].position.y, Node[PulsePointNode].position.z);
	renderSphereVBO();
	glPopMatrix();
	
	// Drawing center node
	//This draws a node at the center of the simulation for debugging purposes
	if(false) // false turns it off, true turns it on.
	{
		glColor3d(0.0,0.0,1.0);
		glPushMatrix();
		glTranslatef(CenterOfSimulation.x, CenterOfSimulation.y, CenterOfSimulation.z);
		renderSphereVBO();
		glPopMatrix();
	}
	
	// Drawing nodes
	if(Simulation.DrawNodesFlag == 1 || Simulation.DrawNodesFlag == 2)  //if we're drawing half(1) or all(2) of the nodes
	{
		for(int i = 0; i < NumberOfNodes; i++) // Start at 1 to skip the pulse node and go through all nodes
		{
			if(Simulation.DrawFrontHalfFlag == 1 || Simulation.DrawNodesFlag == 1) //If we're only drawing the nodes on the front half.
			{
				if(CenterOfSimulation.z - 0.001 < Node[i].position.z)  //Draw only the nodes in the front half.
				{
					glColor3d(Node[i].color.x, Node[i].color.y, Node[i].color.z);
					glPushMatrix();
					glTranslatef(Node[i].position.x, Node[i].position.y, Node[i].position.z);
					renderSphereVBO();
					glPopMatrix();
				}
			}
			else //draw all nodes
			{
				glColor3d(Node[i].color.x, Node[i].color.y, Node[i].color.z);
				glPushMatrix();
				glTranslatef(Node[i].position.x, Node[i].position.y, Node[i].position.z);
				renderSphereVBO();
				glPopMatrix();
			}	
		}
	}
	// If the nodes are not drawn as spheres you will be in this else case.
	// Now some of the node we still draw as points, like node that have been ablated, ectopic nodes, or nodes connected to muscle
	// that have been adjusted. This helps the user keep track of what has been done. This is what is done here and is based on
	// the .isDrawNode flag.
	else 
	{
		glPointSize(NodePointSize);
		glBegin(GL_POINTS);
	 	for(int i = 0; i < NumberOfNodes; i++)
		{
			if(Simulation.DrawFrontHalfFlag == 1)
			{
				if(CenterOfSimulation.z - 0.001 < Node[i].position.z)  // Only drawing the nodes in the front half.
				{
					glColor3d(Node[i].color.x, Node[i].color.y, Node[i].color.z);
					/*if(Node[i].isDrawNode)
					{
						glVertex3f(Node[i].position.x, Node[i].position.y, Node[i].position.z);
					}*/
				}
			}
			else
			{
				glColor3d(Node[i].color.x, Node[i].color.y, Node[i].color.z);
				/*if(Node[i].isDrawNode)
				{
					glVertex3f(Node[i].position.x, Node[i].position.y, Node[i].position.z);
				}*/
			}
		}
		glEnd();
	}

	// Always draw pulse/top/back markers as point sprites so they stand out regardless of node draw mode.
	glPointSize(NodePointSize * 1.35f);
	glBegin(GL_POINTS);
	if(PulsePointNode >= 0 && PulsePointNode < NumberOfNodes)
	{
		glColor3d(1.0, 0.85, 0.2);
		glVertex3f(Node[PulsePointNode].position.x, Node[PulsePointNode].position.y, Node[PulsePointNode].position.z);
	}
	if(UpNode >= 0 && UpNode < NumberOfNodes)
	{
		glColor3d(0.2, 0.95, 1.0);
		glVertex3f(Node[UpNode].position.x, Node[UpNode].position.y, Node[UpNode].position.z);
	}
	if(FrontNode >= 0 && FrontNode < NumberOfNodes)
	{
		glColor3d(1.0, 0.45, 0.2);
		glVertex3f(Node[FrontNode].position.x, Node[FrontNode].position.y, Node[FrontNode].position.z);
	}
	glEnd();
	
	// Drawing muscles
	glLineWidth(LineWidth);
	for(int i = 0; i < NumberOfNodes; i++)
	{
		for(int j = 0; j < MUSCLES_PER_NODE; j++)
		{
			muscleNumber = Node[i].muscle[j];
			if(muscleNumber != -1)
			{
				k = Muscle[muscleNumber].nodeA;
				if(k == i) 
				{
					k = Muscle[muscleNumber].nodeB;
				}
				
				if(Simulation.DrawFrontHalfFlag == 1)
				{
					if(CenterOfSimulation.z - 0.001 < Node[i].position.z && CenterOfSimulation.z - 0.001 < Node[k].position.z)  // Only drawing the nodes in the front half.
					{
						glColor3d(Muscle[muscleNumber].color.x, Muscle[muscleNumber].color.y, Muscle[muscleNumber].color.z);
						glBegin(GL_LINES);
							glVertex3f(Node[i].position.x, Node[i].position.y, Node[i].position.z);
							glVertex3f(Node[k].position.x, Node[k].position.y, Node[k].position.z);
						glEnd();
					}
				}
				else
				{
					glColor3d(Muscle[muscleNumber].color.x, Muscle[muscleNumber].color.y, Muscle[muscleNumber].color.z);
					glBegin(GL_LINES);
						glVertex3f(Node[i].position.x, Node[i].position.y, Node[i].position.z);
						glVertex3f(Node[k].position.x, Node[k].position.y, Node[k].position.z);
					glEnd();
				}
			}
		}	
	}
	
	// Puts a ball at the location of the mouse if a mouse function is on.
	if (Simulation.isInMouseFunctionMode)
	{
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    	glEnable(GL_DEPTH_TEST);
		glColor4f(1.0, 1.0, 1.0, 1.0);
		glPushMatrix();
		glTranslatef(MouseX, MouseY, MouseZ);
		// TODO: define a speicific radius for the sphere so we don't need to repeat calculations.	
		renderSphere(HitMultiplier*RadiusOfLeftAtrium,20,20);
		glPopMatrix();
		glDisable(GL_BLEND);
	}
	
	// Saves the picture if a movie is being recorded.
}

#endif // VIEW_H
