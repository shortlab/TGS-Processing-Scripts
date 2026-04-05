% Script to create window-based interface for TGSPhaseAnalysis. Once this script is opened in MATLAB, click run to start the window.
classdef TGS_GUI < handle
    properties
        UIFigure
        % Inputs
        StartPointEdit
        TwoSAWCheckBox
        BaselineCheckBox
        ClosePlotsCheckBox  % New property
        GratingEdit
        LogFileEdit
        
        % File Path Storage
        PosFiles = {}
        NegFiles = {}
        CalibPosFile = ''
        CalibNegFile = ''
        BaselinePosFile = ''
        BaselineNegFile = ''
        
        % UI Display Components
        CalibFileLabel
        BatchListbox
        BaselineButton
        BaselineFileLabel
    end
    
    methods
        function obj = TGS_GUI()
            obj.createGUI();
        end
        
        function createGUI(obj)
            % Figure size slightly wider to accommodate long paths
            obj.UIFigure = uifigure('Name', 'TGS Analysis Tool', 'Position', [100 100 1050 550]);
            
            % --- 1. Calibration ---
            uilabel(obj.UIFigure, 'Text', '1. Calibration (grating spacing)', 'Position', [20 510 300 22], 'FontWeight', 'bold');
            uibutton(obj.UIFigure, 'Text', 'Select calibration files', 'Position', [20 485 150 22], 'ButtonPushedFcn', @(btn, event) obj.selectCalibFiles());
            obj.CalibFileLabel = uilabel(obj.UIFigure, 'Text', 'No files selected', 'Position', [180 485 850 22], 'FontColor', [0.5 0.5 0.5]);
            uilabel(obj.UIFigure, 'Text', 'Resulting grating (um):', 'Position', [20 455 130 22]);
            obj.GratingEdit = uieditfield(obj.UIFigure, 'numeric', 'Position', [150 455 100 22], 'Value', 0);
            uibutton(obj.UIFigure, 'Text', 'Run calibration', 'Position', [260 455 110 22], 'ButtonPushedFcn', @(btn, event) obj.runCalibration());
            
            % --- 2. Parameters ---
            uilabel(obj.UIFigure, 'Text', '2. Global parameters', 'Position', [20 420 200 22], 'FontWeight', 'bold');
            uilabel(obj.UIFigure, 'Text', 'Start point (1-4):', 'Position', [20 395 100 22]);
            obj.StartPointEdit = uieditfield(obj.UIFigure, 'numeric', 'Position', [120 395 40 22], 'Value', 2);
            
            obj.TwoSAWCheckBox = uicheckbox(obj.UIFigure, 'Text', 'Two SAW', 'Position', [180 395 80 22]);
            
            obj.ClosePlotsCheckBox = uicheckbox(obj.UIFigure, 'Text', 'Close plot windows', 'Position', [270 395 140 22], 'Value', 1);
            
            obj.BaselineCheckBox = uicheckbox(obj.UIFigure, 'Text', 'Use baseline', 'Position', [420 395 100 22], 'ValueChangedFcn', @(cb, event) obj.toggleBaselineUI());
            
            obj.BaselineButton = uibutton(obj.UIFigure, 'Text', 'Select baseline', 'Position', [530 395 110 22], 'Visible', 'off', 'ButtonPushedFcn', @(btn, event) obj.selectBaselineFiles());
            obj.BaselineFileLabel = uilabel(obj.UIFigure, 'Text', 'No baseline selected', 'Position', [650 395 380 22], 'Visible', 'off', 'FontColor', [0.5 0.5 0.5]);
            
            % --- 3. Export Settings ---
            uilabel(obj.UIFigure, 'Text', '3. Export Settings', 'Position', [20 360 200 22], 'FontWeight', 'bold');
            uilabel(obj.UIFigure, 'Text', 'Results Log:', 'Position', [20 335 80 22]);
            obj.LogFileEdit = uieditfield(obj.UIFigure, 'text', 'Position', [100 335 850 22], 'Placeholder', 'Defaults to input folder');
            uibutton(obj.UIFigure, 'Text', 'Browse...', 'Position', [960 335 70 22], 'ButtonPushedFcn', @(btn, event) obj.browseLogFile());
            
            % --- 4. Queue ---
            uilabel(obj.UIFigure, 'Text', '4. Batch processing queue', 'Position', [20 300 200 22], 'FontWeight', 'bold');
            uibutton(obj.UIFigure, 'Text', 'Add files', 'Position', [20 275 100 22], 'ButtonPushedFcn', @(btn, event) obj.addBatchFiles());
            uibutton(obj.UIFigure, 'Text', 'Clear queue', 'Position', [130 275 100 22], 'ButtonPushedFcn', @(btn, event) obj.clearQueue());
            obj.BatchListbox = uilistbox(obj.UIFigure, 'Position', [20 100 1010 165], 'Items', {});
            
            % --- 5. Run ---
            uibutton(obj.UIFigure, 'Text', 'Run batch process', 'Position', [425 25 200 50], 'FontWeight', 'bold', 'ButtonPushedFcn', @(btn, event) obj.runBatch());
        end
        
        %% --- Internal Analysis Methods ---
        function runCalibration(obj)
            if isempty(obj.CalibPosFile), errordlg('Select calibration files.'); return; end
            % Always clear environment before a new run for memory safety
            obj.cleanupEnvironment(true); 
            
            [bBool, bPos, bNeg] = obj.getBaselineParams();
            
            % Initial guess of 10um for calibration
            [freq, ~, ~, ~, ~, ~] = TGSPhaseAnalysis(char(obj.CalibPosFile), char(obj.CalibNegFile), 10, ...
                double(obj.StartPointEdit.Value), double(obj.TwoSAWCheckBox.Value), bBool, bPos, bNeg);
            
            obj.GratingEdit.Value = 10^6 * 2665.9 / freq(1);
            drawnow;
            fprintf('Calibration complete. Frequency: %.4e Hz | Grating: %.4f um\n', freq(1), obj.GratingEdit.Value);
            
            % Explicitly check to close the calibration plots immediately
            if obj.ClosePlotsCheckBox.Value
                close all;
            end
        end
        
        function runBatch(obj)
            if obj.GratingEdit.Value <= 0 || isempty(obj.PosFiles)
                errordlg('Ensure grating is set and queue is populated.');
                return; 
            end
            
            [inputDir, firstFileName] = fileparts(obj.PosFiles{1});
            logInput = strtrim(obj.LogFileEdit.Value);
            if isempty(logInput)
                logPath = fullfile(inputDir, [firstFileName, '_postprocessing.txt']);
            else
                [fDir, fName, fExt] = fileparts(logInput);
                logPath = fullfile(fDir, [fName, fExt]);
                if isempty(fDir), logPath = fullfile(inputDir, [fName, fExt]); end
            end
            
            fid1 = fopen(logPath, 'wt');
            fprintf(fid1,'%s', 'run_name date_time grating_value[um] SAW_freq[Hz] SAW_freq_error[Hz] A[Wm^-2] A_err[Wm^-2] alpha[m^2s^-1] alpha_err[m2s-1] beta[s^0.5] beta_err[s^0.5] B[Wm^-2] B_err[Wm^-2] theta theta_err tau[s] tau_err[s] C[Wm^-2] C_err[Wm^-2]');
            fclose(fid1);
            
            [blbool, baselinePOS, baselineNEG] = obj.getBaselineParams();
            
            clean_grat = double(obj.GratingEdit.Value);
            localStart = double(obj.StartPointEdit.Value);
            localTwoSAW = double(obj.TwoSAWCheckBox.Value);
            localBlBool = logical(blbool);
            
            fprintf('\n--- Starting Batch Process ---\n');
            for i = 1:length(obj.PosFiles)
                [~, runName] = fileparts(obj.PosFiles{i});
                
                % Clean up previous windows before starting next fit
                obj.cleanupEnvironment(obj.ClosePlotsCheckBox.Value);
                
                try
                    [freq, freq_err, speed, diff, diff_err, damping_vec, tauErr, A, A_err, beta, betaErr, B, BErr, theta, thetaErr, C, CErr, file_date_time] = ...
                        TGSPhaseAnalysis(char(obj.PosFiles{i}), char(obj.NegFiles{i}), ...
                        clean_grat, localStart, localTwoSAW, ...
                        localBlBool, char(baselinePOS), char(baselineNEG));
                    
                    fid1 = fopen(logPath, 'a');
                    if fid1 ~= -1
                        tau_val = 0; if length(damping_vec) >= 3, tau_val = damping_vec(3); end
                        fprintf(fid1, '\n%s %s %.8g %0.5e %0.5e %.8g %.8g %.8g %.8g %.8g %.8g %.8g %.8g %.8g %.8g %.8g %.8g %.8g %.8g', ...
                            runName, file_date_time, clean_grat, freq(1), freq_err(1), A, A_err, diff, diff_err, beta, betaErr, B, BErr, theta, thetaErr, tau_val, tauErr, C, CErr);
                        fclose(fid1);
                        fprintf('[%d/%d] SUCCESS: %s\n', i, length(obj.PosFiles), runName);
                    end
                catch ME
                    fprintf('[%d/%d] FAILED: %s (%s)\n', i, length(obj.PosFiles), runName, ME.message);
                end
            end
            
            if obj.ClosePlotsCheckBox.Value
                close all;
            end
            
            fprintf('--- Batch Process Finished ---\n');
        end
        
        %% --- Helper Methods ---
        function [bBool, bPos, bNeg] = getBaselineParams(obj)
            bBool = obj.BaselineCheckBox.Value;
            if bBool
                bPos = obj.BaselinePosFile; bNeg = obj.BaselineNegFile;
            else
                bPos = "dummy.txt"; bNeg = "dummy.txt"; 
            end
        end
        
        function cleanupEnvironment(obj, shouldClose)
            if shouldClose
                close all;
            end
            lastwarn('');
            drawnow; 
        end
        
        function browseLogFile(obj)
            [file, path] = uiputfile('*.txt', 'Specify Results Log File');
            if isequal(file, 0), return; end
            obj.LogFileEdit.Value = fullfile(path, file);
        end
        
        function [matchedPos, matchedNeg] = matchFiles(obj, fileList, path)
            matchedPos = {}; matchedNeg = {};
            if ischar(fileList), fileList = {fileList}; end
            rawPos = {}; rawNeg = {};
            for i = 1:length(fileList)
                if contains(upper(fileList{i}), 'POS'), rawPos{end+1} = fileList{i};
                elseif contains(upper(fileList{i}), 'NEG'), rawNeg{end+1} = fileList{i}; end
            end
            for i = 1:length(rawPos)
                baseID = regexprep(rawPos{i}, 'POS', '', 'ignorecase');
                for j = 1:length(rawNeg)
                    if strcmp(baseID, regexprep(rawNeg{j}, 'NEG', '', 'ignorecase'))
                        matchedPos{end+1} = fullfile(path, rawPos{i});
                        matchedNeg{end+1} = fullfile(path, rawNeg{j});
                        break;
                    end
                end
            end
        end
        
        function toggleBaselineUI(obj)
            state = obj.BaselineCheckBox.Value;
            obj.BaselineButton.Visible = state; obj.BaselineFileLabel.Visible = state;
        end
        
        function selectCalibFiles(obj)
            [files, path] = uigetfile('*.txt', 'Select Calibration files', 'MultiSelect', 'on');
            if isequal(files, 0), return; end
            [p, n] = obj.matchFiles(files, path);
            if isempty(p), errordlg('No matching pair found.');
            else
                obj.CalibPosFile = p{1}; obj.CalibNegFile = n{1};
                [~, pf] = fileparts(p{1}); [~, nf] = fileparts(n{1});
                obj.CalibFileLabel.Text = sprintf('P: %s | N: %s', pf, nf);
            end
        end
        
        function selectBaselineFiles(obj)
            [files, path] = uigetfile('*.txt', 'Select Baseline files', 'MultiSelect', 'on');
            if isequal(files, 0), return; end
            [p, n] = obj.matchFiles(files, path);
            if isempty(p), errordlg('No matching baseline pair.');
            else
                obj.BaselinePosFile = p{1}; obj.BaselineNegFile = n{1};
                [~, pf] = fileparts(p{1}); [~, nf] = fileparts(n{1});
                obj.BaselineFileLabel.Text = sprintf('P: %s | N: %s', pf, nf);
            end
        end
        
        function addBatchFiles(obj)
            [files, path] = uigetfile('*.txt', 'Select TGS files', 'MultiSelect', 'on');
            if isequal(files, 0), return; end
            [pList, nList] = obj.matchFiles(files, path);
            for i = 1:length(pList)
                obj.PosFiles{end+1} = pList{i}; obj.NegFiles{end+1} = nList{i};
                [~, pf] = fileparts(pList{i}); [~, nf] = fileparts(nList{i});
                obj.BatchListbox.Items{end+1} = sprintf('[%d] P: %s | N: %s', length(obj.PosFiles), pf, nf);
            end
        end
        
        function clearQueue(obj)
            obj.PosFiles = {}; obj.NegFiles = {}; obj.BatchListbox.Items = {};
        end
    end
end
