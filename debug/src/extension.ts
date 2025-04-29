import * as vscode from 'vscode';
import { FastMCP, UserError } from 'fastmcp'; 
import { z } from 'zod';


let mcpServer: FastMCP | null = null; // Use original type

function resolvePath(filePath: string): string {
    if (vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders.length > 0) {
        if (filePath.startsWith('/') || filePath.startsWith('\\') || filePath.includes('://')) {
            return vscode.Uri.parse(filePath).fsPath;
        }
        const workspaceUri = vscode.workspace.workspaceFolders[0].uri;
        return vscode.Uri.joinPath(workspaceUri, filePath).fsPath;
    } else if (!filePath.startsWith('/') && !filePath.startsWith('\\') && !filePath.includes('://')){
        throw new UserError('Cannot resolve relative path without an open workspace folder.');
    } 
    return vscode.Uri.parse(filePath).fsPath;
}

export function activate(context: vscode.ExtensionContext) {

   
    console.log('"godot-mcp-debugger" is now active!');

        mcpServer = new FastMCP({
            name: "vscode-debugger-mcp",
            version: "0.1.0",
            instructions: "Provides tools to control the VS Code debugger.",
        });

        mcpServer.addTool({
            name: "start_debugging",
            description: "Starts a VS Code debug session using a launch configuration.",
            parameters: z.object({
                launchConfigurationName: z.string().describe("The name of the launch configuration (e.g., 'Debug Godot GDScript' from launch.json)"),
                workspacePath: z.string().optional().describe("Optional path to the workspace folder containing the launch configuration. Defaults to the first open workspace.")
            }),
            execute: async ({ launchConfigurationName, workspacePath }) => {
                let workspaceFolder: vscode.WorkspaceFolder | undefined;
                if (workspacePath) {
                    const folderUri = vscode.Uri.file(workspacePath);
                    workspaceFolder = vscode.workspace.getWorkspaceFolder(folderUri);
                    if (!workspaceFolder) {
                        throw new UserError(`Workspace folder not found: ${workspacePath}`);
                    }
                } else if (vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders.length > 0) {
                    workspaceFolder = vscode.workspace.workspaceFolders[0];
                } else {
                    throw new UserError("No workspace folder open or specified.");
                }

                try {
                    const success = await vscode.debug.startDebugging(workspaceFolder, launchConfigurationName);
                    if (success) {
                        return `Successfully started debugging session for configuration: ${launchConfigurationName}`;
                    } else {
                        throw new UserError(`Failed to start debugging session for configuration: ${launchConfigurationName}. Check launch configuration and debugger output.`);
                    }
                } catch (error: any) {
                    console.error("Error starting debug session:", error);
                    throw new UserError(`Error starting debug session: ${error.message || error}`);
                }
            },
        });

        mcpServer.addTool({
            name: "stop_debugging",
            description: "Stops the currently active VS Code debug session.",
            parameters: z.object({}), // No parameters
            execute: async () => {
                if (!vscode.debug.activeDebugSession) {
                    return "No active debug session to stop.";
                }
                try {
                    await vscode.debug.stopDebugging();
                    return "Successfully stopped the debug session.";
                } catch (error: any) {
                    console.error("Error stopping debug session:", error);
                    throw new UserError(`Error stopping debug session: ${error.message || error}`);
                }
            },
        });


        mcpServer.addTool({
            name: "add_breakpoint",
            description: "Adds a breakpoint at a specific location in a file.",
            parameters: z.object({
                filePath: z.string().describe("The absolute or workspace-relative path to the file."),
                lineNumber: z.number().int().positive().describe("The 1-based line number for the breakpoint."),
                condition: z.string().optional().describe("Optional condition for the breakpoint (e.g., 'i > 5')."),
                logMessage: z.string().optional().describe("Optional message to log when the breakpoint is hit."),
                hitCondition: z.string().optional().describe("Optional hit count condition (e.g., '5', '>=10').")
            }),
            execute: async ({ filePath, lineNumber, condition, logMessage, hitCondition }) => {
                try {
                    const resolvedPath = resolvePath(filePath);
                    const location = new vscode.Location(vscode.Uri.file(resolvedPath), new vscode.Position(lineNumber - 1, 0)); // Line number is 0-based in Position
                    const breakpoint = new vscode.SourceBreakpoint(location, true, condition, hitCondition, logMessage);

                    vscode.debug.addBreakpoints([breakpoint]);
                    return `Breakpoint added at ${filePath}:${lineNumber}`;
                } catch (error: any) {
                     console.error("Error adding breakpoint:", error);
                    throw new UserError(`Error adding breakpoint: ${error.message || error}`);
                }
            },
        });

        mcpServer.addTool({
            name: "remove_breakpoint",
            description: "Removes a breakpoint from a specific location.",
            parameters: z.object({
                filePath: z.string().describe("The absolute or workspace-relative path to the file where the breakpoint exists."),
                lineNumber: z.number().int().positive().describe("The 1-based line number of the breakpoint to remove.")
            }),
            execute: async ({ filePath, lineNumber }) => {
                try {
                    const resolvedPath = resolvePath(filePath);
                    const uri = vscode.Uri.file(resolvedPath);
                    const existingBreakpoints = vscode.debug.breakpoints;

                    const breakpointToRemove = existingBreakpoints.find(bp =>
                        bp instanceof vscode.SourceBreakpoint &&
                        bp.location.uri.fsPath === uri.fsPath &&
                        bp.location.range.start.line === lineNumber - 1 // Compare 0-based line
                    );

                    if (breakpointToRemove) {
                        vscode.debug.removeBreakpoints([breakpointToRemove]);
                        return `Breakpoint removed from ${filePath}:${lineNumber}`;
                    } else {
                        return `No breakpoint found at ${filePath}:${lineNumber} to remove.`;
                    }
                } catch (error: any) {
                    console.error("Error removing breakpoint:", error);
                    throw new UserError(`Error removing breakpoint: ${error.message || error}`);
                }
            },
        });

         mcpServer.addTool({
            name: "list_breakpoints",
            description: "Lists all currently set breakpoints.",
            parameters: z.object({}),
            execute: async () => {
                const allBreakpoints = vscode.debug.breakpoints;
                if (allBreakpoints.length === 0) {
                    return "No breakpoints are currently set.";
                }

                let report = "Current Breakpoints:\\n";
                allBreakpoints.forEach((bp, index) => {
                    report += `${index + 1}. `;
                    if (bp instanceof vscode.SourceBreakpoint) {
                        report += `File: ${bp.location.uri.fsPath}, Line: ${bp.location.range.start.line + 1}`;
                        report += `, Enabled: ${bp.enabled}`;
                        if (bp.condition) report += `, Condition: ${bp.condition}`;
                        if (bp.hitCondition) report += `, Hit Condition: ${bp.hitCondition}`;
                        if (bp.logMessage) report += `, Log Message: ${bp.logMessage}`;
                    } else if (bp instanceof vscode.FunctionBreakpoint) {
                        report += `Function: ${bp.functionName}`;
                        report += `, Enabled: ${bp.enabled}`;
                         if (bp.condition) report += `, Condition: ${bp.condition}`;
                        if (bp.hitCondition) report += `, Hit Condition: ${bp.hitCondition}`;
                    } else {
                         report += `Unknown type: ${bp.id}`; // DataBreakpoint or InstructionBreakpoint (less common)
                    }
                     report += "\\n";
                });
                return report.trim();
            },
        });

         mcpServer.addTool({
            name: "remove_all_breakpoints",
            description: "Removes all currently set breakpoints.",
            parameters: z.object({}),
            execute: async () => {
                const currentBreakpoints = vscode.debug.breakpoints;
                 if (currentBreakpoints.length === 0) {
                     return "No breakpoints to remove.";
                }
                try {
                     vscode.debug.removeBreakpoints(currentBreakpoints);
                    return `Removed ${currentBreakpoints.length} breakpoint(s).`;
                } catch (error: any) {
                     console.error("Error removing all breakpoints:", error);
                    throw new UserError(`Error removing all breakpoints: ${error.message || error}`);
                }
            },
        });
         
         mcpServer.addTool({
            name: "set_exception_breakpoints",
            description: "Configures debugger behavior for exceptions.",
            parameters: z.object({
                filters: z.array(z.string()).describe("List of exception filter IDs to enable (e.g., ['uncaught', 'caught']). Available filters depend on the debug adapter.")
            }),
            execute: async ({ filters }) => {
                if (!vscode.debug.activeDebugSession) {
                     throw new UserError("No active debug session to set exception breakpoints.");
                 }
                try {
                    await vscode.debug.activeDebugSession.customRequest('setExceptionBreakpoints', { filters });
                    return `Successfully set exception breakpoint filters: ${filters.join(', ')}`;
                } catch (error: any) {
                    console.error("Error setting exception breakpoints:", error);
                     if (error.message && error.message.includes('not supported')) {
                         return "The active debug adapter does not support setting exception breakpoints via custom request.";
                     }
                    throw new UserError(`Error setting exception breakpoints: ${error.message || error}`);
                }
            },
        });


        const executeDebugCommand = async (command: string) => {
            if (!vscode.debug.activeDebugSession) {
                throw new UserError("No active debug session.");
            }
            try {
                // Use customRequest as the primary mechanism for stepping/continuing
                await vscode.debug.activeDebugSession.customRequest(command);
                return `Successfully executed '${command}'.`;
            } catch (error: any) {
                 console.error(`Error executing debug command '${command}':`, error);
                throw new UserError(`Error executing '${command}': ${error.message || error}`);
            }
        };

        mcpServer.addTool({
            name: "continue_execution",
            description: "Continues execution of the paused debugger.",
            parameters: z.object({}),
            execute: () => executeDebugCommand('continue'),
        });

        mcpServer.addTool({
            name: "step_over",
            description: "Steps over the current line in the debugger.",
            parameters: z.object({}),
            execute: () => executeDebugCommand('next'),
        });

        mcpServer.addTool({
            name: "step_into",
            description: "Steps into the function call on the current line.",
            parameters: z.object({}),
            execute: () => executeDebugCommand('stepIn'),
        });

        mcpServer.addTool({
            name: "step_out",
            description: "Steps out of the current function.",
            parameters: z.object({}),
            execute: () => executeDebugCommand('stepOut'),
        });

        mcpServer.addTool({
            name: "restart_debugging",
            description: "Restarts the current debugging session.",
            parameters: z.object({}),
            execute: async () => {
                if (!vscode.debug.activeDebugSession) {
                     throw new UserError("No active debug session to restart.");
                 }
                try {
                     await vscode.debug.activeDebugSession.customRequest('restart');
                     return "Successfully requested debug session restart.";
                 } catch (error: any) {
                     console.error("Error restarting debug session:", error);
                     if (error.message && error.message.includes('not supported')) {
                         return "The active debug adapter does not support the 'restart' request. Stop and start manually.";
                     }
                     throw new UserError(`Error restarting debug session: ${error.message || error}`);
                 }
            },
        });

        mcpServer.addTool({
            name: "get_stack_trace",
            description: "Gets the current call stack from the debugger.",
            parameters: z.object({
                 threadId: z.number().int().optional().describe("Optional ID of the thread to get the stack trace for. Defaults to the thread that caused the stop.")
            }),
            execute: async ({ threadId }) => {
                 if (!vscode.debug.activeDebugSession) {
                     throw new UserError("No active debug session.");
                 }
                try {
                    // Find the correct thread ID if not provided or invalid
                    // This might require inspecting the stopped event details, which isn't directly accessible here.
                    // For simplicity, we'll try requesting thread 1 if none is active or provided, 
                    // but the debug adapter might require a valid threadId from a 'stopped' event.
                    // A robust solution might involve listening to debug events.
                     const session = vscode.debug.activeDebugSession;
                     const threadsResponse = await session.customRequest('threads');
                     let targetThreadId = threadId;

                     if (!targetThreadId) {
                         // Attempt to find a reasonable default thread ID if none provided
                         // This often involves listening to the 'stopped' event, which isn't easily done synchronously here.
                         // As a fallback, try the first thread reported by the adapter.
                         if (threadsResponse && threadsResponse.threads && threadsResponse.threads.length > 0) {
                             targetThreadId = threadsResponse.threads[0].id;
                             console.log(`No threadId provided, using first available thread: ${targetThreadId}`);
                         } else {
                            throw new UserError("Could not determine a valid thread ID. Debug session might not be stopped or has no active threads.");
                         }
                     }
                    
                    const response = await session.customRequest('stackTrace', { threadId: targetThreadId });
                    if (response && response.stackFrames) {
                        // Format the stack trace for readability
                        const formattedStack = response.stackFrames.map((frame: any) => 
                            `${frame.name} (${frame.source ? frame.source.path : 'unknown'} : ${frame.line})`
                        ).join('\n');
                        return `Current Stack Trace (Thread ${targetThreadId}):\n${formattedStack}`;
                    } else {
                        return "Could not retrieve stack trace or stack is empty.";
                    }
                } catch (error: any) {
                    console.error("Error getting stack trace:", error);
                     // Check if the error indicates the thread is running
                     if (error.message && (error.message.includes('is running') || error.message.includes('not stopped'))) {
                        return "Cannot get stack trace: The debug session is currently running.";
                     }
                    throw new UserError(`Error getting stack trace: ${error.message || error}`);
                }
            },
        });

       mcpServer.addTool({
            name: "get_variables",
            description: "Gets the variables in the current scope or a specific scope.",
            parameters: z.object({
                stackFrameId: z.number().int().optional().describe("Optional ID of the stack frame to get variables for. If omitted, variables from the top frame might be fetched (adapter-dependent)."),
                // Note: Getting scopes first and then variables for a scopeReference is the typical DAP flow.
                // Simplifying here to fetch variables directly, which might rely on adapter defaults.
            }),
            execute: async ({ stackFrameId }) => {
                if (!vscode.debug.activeDebugSession) {
                    throw new UserError("No active debug session.");
                }
                try {
                    const session = vscode.debug.activeDebugSession;

                    // 1. Get Scopes for the target frame (or default frame)
                    let targetFrameId = stackFrameId;
                    if (!targetFrameId) {
                        // Need to get the top stack frame ID first if none specified
                         const threadsResponse = await session.customRequest('threads');
                         if (!threadsResponse || !threadsResponse.threads || threadsResponse.threads.length === 0) {
                             throw new UserError("Could not determine thread ID to fetch stack trace.");
                         }
                         const firstThreadId = threadsResponse.threads[0].id;
                         const stackTraceResponse = await session.customRequest('stackTrace', { threadId: firstThreadId, levels: 1 }); // Get only top frame
                        if (!stackTraceResponse || !stackTraceResponse.stackFrames || stackTraceResponse.stackFrames.length === 0) {
                            throw new UserError("Could not get the top stack frame.");
                        }
                        targetFrameId = stackTraceResponse.stackFrames[0].id;
                        console.log(`No stackFrameId provided, using top frame ID: ${targetFrameId}`);
                    }

                    const scopesResponse = await session.customRequest('scopes', { frameId: targetFrameId });
                    if (!scopesResponse || !scopesResponse.scopes) {
                        throw new UserError(`Could not retrieve scopes for stack frame ID: ${targetFrameId}`);
                    }

                    // 2. Get Variables for each scope
                    let variablesResult = `Variables for Stack Frame ${targetFrameId}:\\n`;
                    for (const scope of scopesResponse.scopes) {
                        variablesResult += `\\n--- Scope: ${scope.name} (Ref: ${scope.variablesReference}, Expensive: ${scope.expensive}) ---\\n`; // Also show scope ref
                        const variablesResponse = await session.customRequest('variables', { variablesReference: scope.variablesReference });
                        if (variablesResponse && variablesResponse.variables) {
                            if (variablesResponse.variables.length === 0) {
                                variablesResult += " (No variables in this scope)\\n";
                            } else {
                                variablesResponse.variables.forEach((variable: any) => {
                                    variablesResult += ` ${variable.name}: ${variable.value}`;
                                    if (variable.type) {
                                        variablesResult += ` (${variable.type})`;
                                    }
                                    // ADDED: Include variablesReference if > 0
                                    if (variable.variablesReference > 0) {
                                        variablesResult += ` [Ref: ${variable.variablesReference}]`;
                                    }
                                    variablesResult += "\\n";
                                });
                            }
                        } else {
                             variablesResult += " (Could not retrieve variables for this scope)\\n";
                        }
                    }

                    return variablesResult.trim();
                    
                } catch (error: any) {
                    console.error("Error getting variables:", error);
                     if (error.message && (error.message.includes('is running') || error.message.includes('not stopped'))) {
                        return "Cannot get variables: The debug session is currently running.";
                     }
                    throw new UserError(`Error getting variables: ${error.message || error}`);
                }
            },
        });

        mcpServer.addTool({
            name: "get_variable_details",
            description: "Gets the nested contents (elements, properties, key-value pairs) of a structured variable using its variablesReference.",
            parameters: z.object({
                variablesReference: z.number().int().positive().describe("The 'variablesReference' ID of the structured variable (obtained from 'get_variables', 'get_scopes', or 'evaluate_expression').")
            }),
            execute: async ({ variablesReference }) => {
                if (!vscode.debug.activeDebugSession) {
                    throw new UserError("No active debug session.");
                }
                try {
                    const session = vscode.debug.activeDebugSession;
                    const response = await session.customRequest('variables', { variablesReference: variablesReference });

                    if (response && response.variables) {
                        if (response.variables.length === 0) {
                            return `Variable (Ref: ${variablesReference}) has no contents or is empty.`;
                        }
                        let detailsResult = `Contents for Variable (Ref: ${variablesReference}):\\n`;
                        response.variables.forEach((variable: any) => {
                            detailsResult += ` ${variable.name}: ${variable.value}`;
                            if (variable.type) {
                                detailsResult += ` (${variable.type})`;
                            }
                            if (variable.variablesReference > 0) {
                                detailsResult += ` [Ref: ${variable.variablesReference}]`; // Show nested Ref
                            }
                            detailsResult += "\\n";
                        });
                        return detailsResult.trim();
                    } else {
                        return `Could not retrieve details for variable reference: ${variablesReference}`;
                    }
                } catch (error: any) {
                    console.error("Error getting variable details:", error);
                    if (error.message && (error.message.includes('is running') || error.message.includes('not stopped'))) {
                        return `Cannot get variable details (Ref: ${variablesReference}): The debug session is currently running.`;
                    }
                    if (error.message && error.message.includes('indexed variables')) {
                         return `Cannot get variable details (Ref: ${variablesReference}): This variable might be too large or complex for simple expansion. Consider evaluating specific properties/indices.`;
                     }
                    throw new UserError(`Error getting variable details (Ref: ${variablesReference}): ${error.message || error}`);
                }
            },
        });

        mcpServer.addTool({
            name: "get_scopes",
            description: "Gets the available scopes (like Locals, Arguments, Registers) for a specific stack frame.",
            parameters: z.object({
                stackFrameId: z.number().int().optional().describe("Optional ID of the stack frame to get scopes for. If omitted, scopes from the top frame might be fetched."),
            }),
            execute: async ({ stackFrameId }) => {
                if (!vscode.debug.activeDebugSession) {
                    throw new UserError("No active debug session.");
                }
                try {
                    const session = vscode.debug.activeDebugSession;
                    let targetFrameId = stackFrameId;

                    // Resolve targetFrameId if not provided (similar logic to get_variables)
                    if (!targetFrameId) {
                        const threadsResponse = await session.customRequest('threads');
                        if (!threadsResponse?.threads?.length) throw new UserError("Could not determine thread ID.");
                        const firstThreadId = threadsResponse.threads[0].id;
                        const stackTraceResponse = await session.customRequest('stackTrace', { threadId: firstThreadId, levels: 1 });
                        if (!stackTraceResponse?.stackFrames?.length) throw new UserError("Could not get the top stack frame.");
                        targetFrameId = stackTraceResponse.stackFrames[0].id;
                        console.log(`No stackFrameId provided for get_scopes, using top frame ID: ${targetFrameId}`);
                    }

                    const scopesResponse = await session.customRequest('scopes', { frameId: targetFrameId });
                    if (!scopesResponse || !scopesResponse.scopes) {
                        throw new UserError(`Could not retrieve scopes for stack frame ID: ${targetFrameId}`);
                    }

                    if (scopesResponse.scopes.length === 0) {
                        return `No scopes found for stack frame ID: ${targetFrameId}.`;
                    }

                    let scopesResult = `Scopes for Stack Frame ${targetFrameId}:\\n`;
                    scopesResponse.scopes.forEach((scope: any) => {
                        scopesResult += ` - Name: ${scope.name}, Ref: ${scope.variablesReference}, Expensive: ${scope.expensive}\\n`;
                    });
                    return scopesResult.trim();

                } catch (error: any) {
                     console.error("Error getting scopes:", error);
                    if (error.message && (error.message.includes('is running') || error.message.includes('not stopped'))) {
                        return "Cannot get scopes: The debug session is currently running.";
                    }
                    throw new UserError(`Error getting scopes: ${error.message || error}`);
                }
            },
        });

        mcpServer.addTool({
            name: "evaluate_expression",
            description: "Evaluates an expression in the context of a specific stack frame.",
            parameters: z.object({
                expression: z.string().describe("The expression to evaluate (e.g., 'myVar', 'object.property', 'calculate(10)')."),
                stackFrameId: z.number().int().optional().describe("Optional ID of the stack frame context. If omitted, the top frame is typically used."),
                context: z.enum(['watch', 'repl', 'hover', 'clipboard']).optional().describe("Evaluation context hint (e.g., 'watch', 'repl'). Defaults to 'repl' if omitted.")
            }),
            execute: async ({ expression, stackFrameId, context }) => {
                if (!vscode.debug.activeDebugSession) {
                    throw new UserError("No active debug session.");
                }
                try {
                    const session = vscode.debug.activeDebugSession;
                     let targetFrameId = stackFrameId;

                     if (!targetFrameId) {
                        const threadsResponse = await session.customRequest('threads');
                        if (!threadsResponse?.threads?.length) throw new UserError("Could not determine thread ID.");
                        const firstThreadId = threadsResponse.threads[0].id;
                        const stackTraceResponse = await session.customRequest('stackTrace', { threadId: firstThreadId, levels: 1 });
                        if (!stackTraceResponse?.stackFrames?.length) throw new UserError("Could not get the top stack frame.");
                        targetFrameId = stackTraceResponse.stackFrames[0].id;
                     }

                    const response = await session.customRequest('evaluate', {
                        expression: expression,
                        frameId: targetFrameId,
                        context: context || 'repl' // Default context to 'repl'
                    });

                    if (response) {
                         // Format the result simply
                         // DAP 'evaluate' response structure: { result: string, type?: string, variablesReference: number, ... }
                         let resultString = `Expression: ${expression}\\nResult: ${response.result}`;
                         if (response.type) {
                             resultString += ` (Type: ${response.type})`;
                         }
                         // If variablesReference > 0, it means the result is structured and can be further inspected
                         // For simplicity, we don't automatically expand here, but mention it.
                         if (response.variablesReference > 0) {
                             resultString += `\\n(Note: Result is structured. Use 'get_variables' with the appropriate reference if needed, though this tool doesn't directly return the reference ID).`;
                             // A more advanced version could return the variablesReference or even call 'variables' automatically.
                         }
                        return resultString;
                    } else {
                        return `Evaluation of '${expression}' did not return a result.`;
                    }
                } catch (error: any) {
                    console.error("Error evaluating expression:", error);
                     if (error.message && (error.message.includes('is running') || error.message.includes('not stopped'))) {
                         return "Cannot evaluate expression: The debug session is currently running.";
                     }
                     if (error.message && error.message.includes('not available')) {
                         return `Evaluation failed: ${error.message}` // Common error for invalid expressions
                     }
                    throw new UserError(`Error evaluating expression '${expression}': ${error.message || error}`);
                }
            },
        });

        const findBreakpoint = (filePath: string, lineNumber: number): vscode.SourceBreakpoint | undefined => {
            const resolvedPath = resolvePath(filePath);
            const uri = vscode.Uri.file(resolvedPath);
            return vscode.debug.breakpoints.find(bp =>
                bp instanceof vscode.SourceBreakpoint &&
                bp.location.uri.fsPath === uri.fsPath &&
                bp.location.range.start.line === lineNumber - 1 // Compare 0-based line
            ) as vscode.SourceBreakpoint | undefined;
        };

        const updateBreakpoint = async (
            filePath: string,
            lineNumber: number,
            updates: Partial<Pick<vscode.SourceBreakpoint, 'enabled' | 'condition' | 'hitCondition' | 'logMessage'>>
        ): Promise<string> => {
            const existingBreakpoint = findBreakpoint(filePath, lineNumber);
            if (!existingBreakpoint) {
                return `No breakpoint found at ${filePath}:${lineNumber} to update.`;
            }

            try {
                // Create a new breakpoint instance with updated properties
                const newBreakpoint = new vscode.SourceBreakpoint(
                    existingBreakpoint.location,
                    updates.enabled ?? existingBreakpoint.enabled,
                    updates.condition ?? existingBreakpoint.condition,
                    updates.hitCondition ?? existingBreakpoint.hitCondition,
                    updates.logMessage ?? existingBreakpoint.logMessage
                );

                // Remove the old one and add the new one
                vscode.debug.removeBreakpoints([existingBreakpoint]);
                vscode.debug.addBreakpoints([newBreakpoint]);

                 let updateDesc = Object.keys(updates).join(', ');
                return `Breakpoint at ${filePath}:${lineNumber} updated (${updateDesc}).`;

            } catch (error: any) {
                console.error(`Error updating breakpoint at ${filePath}:${lineNumber}:`, error);
                 // Attempt to re-add the original breakpoint if update failed? Maybe too complex.
                throw new UserError(`Error updating breakpoint: ${error.message || error}`);
            }
        };

        mcpServer.addTool({
            name: "enable_breakpoint",
            description: "Enables a specific breakpoint.",
            parameters: z.object({
                filePath: z.string().describe("The absolute or workspace-relative path to the file."),
                lineNumber: z.number().int().positive().describe("The 1-based line number of the breakpoint."),
            }),
            execute: ({ filePath, lineNumber }) => updateBreakpoint(filePath, lineNumber, { enabled: true }),
        });

        mcpServer.addTool({
            name: "disable_breakpoint",
            description: "Disables a specific breakpoint without removing it.",
            parameters: z.object({
                filePath: z.string().describe("The absolute or workspace-relative path to the file."),
                lineNumber: z.number().int().positive().describe("The 1-based line number of the breakpoint."),
            }),
            execute: ({ filePath, lineNumber }) => updateBreakpoint(filePath, lineNumber, { enabled: false }),
        });

        mcpServer.addTool({
            name: "modify_breakpoint",
            description: "Modifies the properties (condition, hit condition, log message) of an existing breakpoint.",
            parameters: z.object({
                filePath: z.string().describe("The absolute or workspace-relative path to the file."),
                lineNumber: z.number().int().positive().describe("The 1-based line number of the breakpoint."),
                condition: z.string().optional().describe("New condition for the breakpoint (e.g., 'i > 5'). Empty string or null clears it."),
                hitCondition: z.string().optional().describe("New hit count condition (e.g., '5', '>=10'). Empty string or null clears it."),
                logMessage: z.string().optional().describe("New message to log when the breakpoint is hit. Empty string or null clears it."),
            }),
            execute: async ({ filePath, lineNumber, condition, hitCondition, logMessage }) => {
                 const updates: Partial<Pick<vscode.SourceBreakpoint, 'condition' | 'hitCondition' | 'logMessage'>> = {};
                 if (condition !== undefined) updates.condition = condition ?? undefined; // Map null/empty string to undefined for removal
                 if (hitCondition !== undefined) updates.hitCondition = hitCondition ?? undefined;
                 if (logMessage !== undefined) updates.logMessage = logMessage ?? undefined;

                 if (Object.keys(updates).length === 0) {
                    return `No properties provided to modify for breakpoint at ${filePath}:${lineNumber}.`;
                 }

                 return updateBreakpoint(filePath, lineNumber, updates);
             }
        });


        mcpServer.addTool({
            name: "set_variable",
            description: "Sets the value of a variable in a specific scope. Use with caution.",
            parameters: z.object({
                scopeVariablesReference: z.number().int().positive().describe("The 'variablesReference' ID of the scope (e.g., Locals, Arguments) obtained from 'get_variables' or 'scopes' request."),
                variableName: z.string().describe("The name of the variable to set within that scope."),
                newValue: z.string().describe("The new value to assign to the variable (as a string). The debug adapter will attempt to parse it.")
                // Note: Requires knowing the variablesReference of the *scope*, not the variable itself.
                // Getting this requires a 'scopes' request first. Let's adjust get_variables slightly or add get_scopes.
                // For now, we'll assume the user can get this ID somehow (maybe from a previous get_variables call if we modified it).
                // Let's add a simplified helper to get the locals scope reference first.
            }),
            execute: async ({ scopeVariablesReference, variableName, newValue }) => {
                 if (!vscode.debug.activeDebugSession) {
                    throw new UserError("No active debug session.");
                }
                
                try {
                    const session = vscode.debug.activeDebugSession;

                    const response = await session.customRequest('setVariable', {
                        variablesReference: scopeVariablesReference, // This needs to be the reference for the SCOPE (e.g., Locals)
                        name: variableName,
                        value: newValue
                    });

                    if (response && response.value !== undefined) {
                        let result = `Successfully set variable '${variableName}' to: ${response.value}`;
                        if(response.type) result += ` (Type: ${response.type})`;
                        return result;
                    } else {
                        return `Request to set variable '${variableName}' sent. Check debugger state to confirm.`
                    }

                } catch (error: any) {
                    console.error("Error setting variable:", error);
                    if (error.message && (error.message.includes('is running') || error.message.includes('not stopped'))) {
                         return "Cannot set variable: The debug session is currently running.";
                     }
                    if (error.message && error.message.includes('not supported')) {
                         return "The active debug adapter may not support setting variables.";
                     }
                     if (error.message && error.message.includes('failed')) {
                         return `Failed to set variable '${variableName}': ${error.message}`; // e.g., type mismatch, invalid scope
                     }
                    throw new UserError(`Error setting variable '${variableName}': ${error.message || error}`);
                }
            },
        });

        console.log('Starting MCP server...');
        mcpServer.start({
                transportType: "sse",
                sse: {
                    port: 8081, // Using port 8081
                    endpoint: "/mcp-debugger" // Using endpoint /mcp-debugger
                }
            })
            .then(() => {
                console.log('MCP server started successfully using SSE on port 8081.');
            })
            .catch(error => {
                console.error('Failed to start MCP server:', error);
                vscode.window.showErrorMessage(`Failed to start Godot MCP Debugger server: ${error}`);
            });

        let disposable = vscode.commands.registerCommand('godot-mcp-debugger.helloWorld', () => {
            vscode.window.showInformationMessage('Hello from Godot MCP Debugger!');
        });

        context.subscriptions.push(disposable);
}

export function deactivate() {
    console.log('Deactivating "godot-mcp-debugger"...');
    mcpServer = null;
    console.log('"godot-mcp-debugger" deactivated.');
} 