#ifndef GUI_H
#define GUI_H

#include "globals.h"
#include "view.h"
#include "callbacks.h"
#include "utils.h"

static inline void ShowTooltip(const char* text)
{
	if (ImGui::IsItemHovered())
	{
		ImGui::BeginTooltip();
		ImGui::TextUnformatted(text);
		ImGui::EndTooltip();
	}
}

void createGUI()
{

	// Get actual viewport size -- this is the size of the window, not the size of the the openGL viewport
	const ImGuiViewport* viewport = ImGui::GetMainViewport();

	//status panel: always visible so the user knows whether simulation is in GUI mode or mouse mode.
	ImGui::SetNextWindowPos(ImVec2(viewport->WorkPos.x + 10, viewport->WorkPos.y + 10), ImGuiCond_Always, ImVec2(0.0f, 0.0f));
	ImGuiWindowFlags status_flags = ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoFocusOnAppearing | ImGuiWindowFlags_NoSavedSettings;
	ImGui::Begin("Interaction Mode", NULL, status_flags);
	if (!Simulation.isInMouseFunctionMode)
	{
		ImGui::TextColored(ImVec4(0.2f, 0.9f, 0.2f, 1.0f), "GUI Mode");
		ImGui::TextUnformatted("Mouse editing disabled");
	}
	else
	{
		ImGui::TextColored(ImVec4(1.0f, 0.75f, 0.2f, 1.0f), "Mouse Mode");
		if (Simulation.mouseMode == MOUSE_MODE_STANDARD) ImGui::TextUnformatted("Section: Standard");
		else if (Simulation.mouseMode == MOUSE_MODE_BACHMANNS_BUNDLE) ImGui::TextUnformatted("Section: Bachmann's Bundle");
		else if (Simulation.mouseMode == MOUSE_MODE_APPENDAGE) ImGui::TextUnformatted("Section: Appendage");
		else if (Simulation.mouseMode == MOUSE_MODE_SCAR_TISSUE) ImGui::TextUnformatted("Section: Scar Tissue");
		else if (Simulation.mouseMode == MOUSE_MODE_PULMONARY_VEINS) ImGui::TextUnformatted("Section: Pulmonary Veins");
		else if (Simulation.mouseMode == MOUSE_MODE_MITRAL_VALVE) ImGui::TextUnformatted("Section: Mitral Valve");
		else if (Simulation.mouseMode == MOUSE_MODE_PULSE_NODE) ImGui::TextUnformatted("Section: Pulse Node");
		else if (Simulation.mouseMode == MOUSE_MODE_BACK_TOP) ImGui::TextUnformatted("Section: Back/Top Nodes");
		else ImGui::TextUnformatted("Section: None");
	}
	ImGui::TextUnformatted("Tab: Toggle GUI/Mouse mode");
	if (BinarySaveStatusMessage[0] != '\0')
	{
		ImGui::Separator();
		ImGui::TextWrapped("%s", BinarySaveStatusMessage);
	}
	ImGui::End();

	// Mouse mode hides the control panel to match model behavior.
	if (Simulation.isInMouseFunctionMode)
	{
		return;
	}

	//Set in top right corner of the window, 10px offset from both edges
	//ImGUICond_Always means the position will always be set to this value, regardless of previous positions
	//last arg anchors to the right and top of the window
	ImGui::SetNextWindowPos(ImVec2(viewport->WorkPos.x + viewport->WorkSize.x - 10, viewport->WorkPos.y + 10), ImGuiCond_Always,  ImVec2(1.0f, 0.0f));

    // Setup ImGui window flags
    ImGuiWindowFlags window_flags = 0; // Initialize window flags to 0, flags are used to set window properties, like size, position, etc. 0 means no flags are set
    window_flags = ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoFocusOnAppearing; // Always resize the window to fit the content
    

	// Set the collapsed state if guiCollapsed is true (toggled by ctrl + h callback)
    ImGui::SetNextWindowCollapsed(Simulation.guiCollapsed, ImGuiCond_Always);


    // Main Controls Window
    ImGui::Begin("Control Panel", NULL, window_flags); //title of the window, NULL means no pointer to a bool to close the window, window_flags are the flags we set above
    
	//update bool to match current state (makes sure clicking also works in addition to ctrl + h)
	Simulation.guiCollapsed = ImGui::IsWindowCollapsed();


    
    // General simulation controls
    if (ImGui::CollapsingHeader("Simulation Controls", ImGuiTreeNodeFlags_DefaultOpen)) //open by default
    {
        // View controls
        bool frontHalf = Simulation.DrawFrontHalfFlag == 1; //Needed because ImGui needs a bool for a checkbox, can make a dropbox if more display options are needed
        if(ImGui::Checkbox("Draw Front Half Only", &frontHalf)) //checkbox for if we only want to draw the first half of the nodes
        {
			//when the button is pressed it will change the value of frontHalf to the opposite of what it was before
            Simulation.DrawFrontHalfFlag = frontHalf ? 1 : 0;
            drawPicture();
        }
		ShowTooltip("(F2)");
        
        // Node display options
        const char* nodeOptions[] = { "Off", "Half", "Full" }; //array of options for the dropdown menu
        int nodeDisplay = Simulation.DrawNodesFlag;

		//Combo makes a dropdown menu with the options in the array
        if(ImGui::Combo("Show Nodes", &nodeDisplay, nodeOptions, 3)) //args are menu name, pointer to the selected option, array of text options, # of options
        {
            if (nodeDisplay != Simulation.DrawNodesFlag) // Only update if the value changes
            {
                Simulation.DrawNodesFlag = nodeDisplay;
                drawPicture();
            }
        }
		ShowTooltip("(F3)");

        // Change view
	

	}       
       
	// View presets
	if (ImGui::CollapsingHeader("View Controls", ImGuiTreeNodeFlags_DefaultOpen))//2nd arg is the flags, DefaultOpen means it will be open by default
	{

		if (ImGui::Button("PA"))
		{ 
			setView(4); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(7)\nPosterior-Anterior View\nView from back to front");
		
		ImGui::SameLine();
		if (ImGui::Button("AP"))  
		{
			setView(2); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(8)\nAnterior-Posterior View\nView from front to back");
		
		ImGui::SameLine();
		if (ImGui::Button("Ref"))
		{ 
			setView(6); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(9)\nReference View\nStandard orientation with pulmonary veins visible");
		
		if (ImGui::Button("LAO"))
		{ 
			setView(1); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(4)\nLeft Anterior Oblique\nAngled view from front-left");
		
		ImGui::SameLine();
		if (ImGui::Button("RAO"))
		{ 
			setView(3); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(5)\nRight Anterior Oblique\nAngled view from front-right");
		
		ImGui::SameLine();
		if (ImGui::Button("LL"))
		{ 
			setView(7); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(6)\nLeft Lateral\nDirect view from left side");

		if (ImGui::Button("RL"))
		{ 
			setView(9); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(1)\nRight Lateral\nDirect view from right side");
		
		ImGui::SameLine();
		if (ImGui::Button("SUP"))
		{ 
			setView(8); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(2)\nSuperior View\nView from above (top-down)");
		
		ImGui::SameLine();
		if (ImGui::Button("INF"))
		{ 
			setView(5); 
			//copyNodesToGPU(); 
			drawPicture(); 
		}
		ShowTooltip("(3)\nInferior View\nView from below (bottom-up)");
	}
	
	// Mouse mode selection
	if (ImGui::CollapsingHeader("Mouse Functions", ImGuiTreeNodeFlags_DefaultOpen))
	{
		// Mouse mode buttons
		// TODO: Implement the mouse mode defines here.
		if (ImGui::Button("Mouse Off"))
		{
			setMouseMode(&Simulation, MOUSE_MODE_OFF); // OR whatever number for simulation off 
		}
		ShowTooltip("Disable mouse editing and return to GUI mode");

		if (ImGui::Button("Set Standard Node")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_STANDARD); 
		}
		// TODO: Make helper functions for tooltips
		ShowTooltip("(F4)\nSet selected nodes to Standard");

		if (ImGui::Button("Set Bachmann's Bundle")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_BACHMANNS_BUNDLE);
		}
		ShowTooltip("(F5)\nSet selected nodes to Bachmann's Bundle");
		if (ImGui::Button("Set Appendage")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_APPENDAGE);
		}
		ShowTooltip("(F6)\nSet selected nodes to Appendage");
		if (ImGui::Button("Set Scar/Extra Tissue")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_SCAR_TISSUE); 
		}
		ShowTooltip("(F7)\nSet selected nodes to Scar Tissue");

		if (ImGui::Button("Set Pulse Node")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_PULSE_NODE); 
		}
		ShowTooltip("Click a node to set it as the pulse node");

		if (ImGui::Button("Set Back/Top Nodes")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_BACK_TOP); 
		}
		ShowTooltip("Click a back node; the top node is calculated from type 0 wall nodes");

		if (ImGui::Button("Set Pulmonary Veins")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_PULMONARY_VEINS); 
		}
		ShowTooltip("(F8)\nSet selected nodes to Pulmonary Veins");

		if (ImGui::Button("Set Mitral Valve")) 
		{
			setMouseMode(&Simulation, MOUSE_MODE_MITRAL_VALVE); 
		}
		ShowTooltip("(F9)\nSet selected nodes to Mitral Valve");

	}
    
    // Utility functions
	if (ImGui::CollapsingHeader("Utilities", ImGuiTreeNodeFlags_DefaultOpen))
    {
		if (ImGui::Button("Reset"))
		{
			resetToOriginalOrClear();
		}
		ShowTooltip("Reset to original binary state (if .bin), otherwise clear all types");

		ImGui::SameLine();
		if (ImGui::Button("Clear All"))
		{
			clearAllTypes();
		}
		ShowTooltip("Clear all node/muscle types to default (Standard)");

		if (ImGui::Button("Save Binary"))
		{
			saveBinary();
		}
		ShowTooltip("(Ctrl + Shift + S)\nSave node/muscle attributes to\n<NodesMusclesFileName>_<timestamp>.bin");

		if (BinarySaveStatusMessage[0] != '\0')
		{
			ImGui::TextWrapped("%s", BinarySaveStatusMessage);
		}
    }

	//Display movement controls
	if (ImGui::CollapsingHeader("Keyboard Controls"))
	{

		ImGui::Text("Quit: esc");
		ImGui::NewLine(); //add a new line for spacing
		ImGui::Text("Rotate X-axis: a/d; Left/Right");
		ImGui::Text("Rotate Y-axis: w/s; Up/Down");
		ImGui::Text("Rotate Z-axis: z/Z; Shift + Left/Right");
		ImGui::Text("Zoom In/Out: e/E; Shift + Up/Down");
		ImGui::Text("Toggle GUI/Mouse mode: Tab");

		ImGui::Text("Collapse/Expand GUI: Ctrl + h");
		
	}
    
    ImGui::End(); //end the main controls window
    
  
}
#endif // GUI_H
