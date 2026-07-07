#ifndef CUDAFUNCTIONS_H
#define CUDAFUNCTIONS_H

#include "header.h"  // for structure definitions

// prototypes for CUDA kernels and helper functions

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

#endif // CUDAFUNCTIONS_H


