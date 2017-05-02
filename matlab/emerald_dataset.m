classdef emerald_dataset
% emerald_dataset  A container for functions for handling a single Emerald dataset
%
% Typically, a single Emerald dataset is a single sweep from a single volume.
% Object oriented classes here are only used to lump the dataset functions into a single
% container.  This class does not need to be instantiated.  To call any function, 
% just call like:
% OUTARGS = emerald_dataset.FUNCTION(INARGS)
%
% available functions:
%  get_cfradial_inventory: obtain inventory info from a CFRadial file
%  load_cfradial: load a CFRadial file and return as a emerald_dataset struct
%  check_dataset: check a (possible struct array of) emerald_data struct(s)
%  check_single_dataset: check a emerald_data struct
%
% to see help on any of these:
% >> help emerald_dataset.FUNCTION
%

% % % ** Copyright (c) 2015, University Corporation for Atmospheric Research
% % % ** (UCAR), Boulder, Colorado, USA.  All rights reserved. 


% $Revision: 1.6 $
  
  methods (Static = true)
    
    
    %%%%%%%%%%%%%%%%%%%%%%%
    %% get_cfradial_inventory
    function [ncinfo,rawncinfo,meta_data_fields,moment_fields,vary_n_gates] = get_cfradial_inventory(varargin)
    % get_cfradial_inventory: Retrieve the data inventory from a cfRadial file.  This does not
    % actually load any moment data, just retrieves the info.
    % usage: [ncinfo,rawncinfo,meta_data_fields,moment_fields,vary_n_gates] = get_cfradial_inventory('param1',value1,...)
    % possible params:
    %  vars = {}; Cell array of variable names to retrieve in the read along with the standard ones
    %
    %  ncinfo: struct organized into an emerald_dataset struct format.
    %  rawncinfo: struct of the same format as the output of NetcdfRead, containing info from the nc file
    %  meta_data_fields is a cell array of field names that are meta-data
    %  moment_fields is a cell array of field names that are moments data.
    %  vary_n_gates is either 1 or 0; 1 if the CfRadial file uses a variable number of gets per radaial
    %
    %  emerald_dataset struct format contains several substructures:
    %   file_info: information about the file
    %   inds_info: information about the upacking of the CFRadial file into multidim arrays. 
    %      probably only useful for saving back into a CFRadial file.
    %   meta_data: struct containing metadata fields
    %   moment_data: struct containing moments
    %   meta_data_info: struct containing NetcdfRead info (without data) for each metadata field
    %   moments_info: struct containing NetcdfRead info (without data) for each moments field
      
      
    % just get variable and dimension ncinfo
      rawncinfo = emerald_dataset.get_cfradial_inventory_nc(varargin{:});
      ncinfo = emerald_dataset.netcdf2emerald(rawncinfo,'sweep_index',inf,'convert_coords',0);
      if nargout>2
        [meta_data_fields,moment_fields,vary_n_gates] = emerald_dataset.determine_fields(rawncinfo);
      end
    end
   
    %%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%% load_cfradial
    function data = load_cfradial(filename,vars,varargin)
    % cfradial: Retrieve the data from a cfRadial file and return as emerald_dataset struct
    % usage: load_cfradial(filename,vars,'param1',value1,...)
    %  filename: string containing filename of CFRadial file
    %  vars: cell array of field names or can be 'all_fields' to load all
    % possible params:
    %  sweep_number = []; % array of sweep numbers ('sweep_number' in CFRadial file) to pull out. If
    %    empty, then the sweep_index will be used.
    %  sweep_index = 1; % array of sweep indices (index of 'sweep_number').  If equal to inf, then 
    %    all sweeps will be loaded.
    %  append_to = {}; % if this is a emerald_dataset struct, then 1 sweep can be appended (i.e. it
    %    just adds more fields to an existing emerald_dataset struct).
    %  do_check = 1; % boolean.  If 1 then it performs a dataset check after loading.
    %  meta_data_fields = {}; % if already known, these can be provided to speed up processing
    %  moments_fields = {}; % if already known, these can be provided to speed up processing
    %  vary_n_gates = []; % if already known, these can be provided to speed up processing
    %  convert_coords = 1; % if 1, try to convert pointing coordinates to lat/lon/alt x/y/z
    %
    %  ncinfo: struct organized into an emerald_dataset struct format.
    %  rawncinfo: struct of the same format as the output of NetcdfRead, containing info from the nc file
    %  meta_data_fields is a cell array of field names that are meta-data
    %  moment_fields is a cell array of field names that are moments data.
    %
    %  emerald_dataset struct format contains several substructures:
    %   file_info: information about the file
    %   inds_info: information about the upacking of the CFRadial file into multidim arrays. 
    %      probably only useful for saving back into a CFRadial file.
    %   meta_data: struct containing metadata fields
    %   moment_data: struct containing moments
    %   meta_data_info: struct containing NetcdfRead info (without data) for each metadata field
    %   moments_info: struct containing NetcdfRead info (without data) for each moments field

      sweep_index = 1;
      sweep_number = [];
      append_to = {};
      do_check = 1;
      
      meta_data_fields = {};
      moments_fields = {};
      vary_n_gates = [];
      convert_coords = 1;
     
      paramparse(varargin);

      if nargin<2
        error('Required inputs missing');
      end

      vars = cellify(vars);

      EC = emerald_errorcodes;

      % if append_to is given, first check to see if it is ok.  Then grab filename and sweep_number.
      if ~isempty(append_to)
        [result,msg] = emerald_dataset.check_dataset(append_to);
        if result
          error(sprintf('Could not append to the provided structure:\n%s',msg));
        end
        filename = append_to.file_info.filename;
        sweep_number = append_to.meta_data.sweep_number;
      end

      if isempty(meta_data_fields) ||  isempty(vary_n_gates)
        [~,meta_data_fields,moments_fields,vary_n_gates] = emerald_dataset.get_cfradial_inventory_nc(filename);      
      end
      
      if isequal(vars,{'all_fields'})
        % in special case that vars = {'all_fields'} then grab all fields
        vars = moments_fields;
      else
        % otherwise, check that all given fields are valid
        fields_exist = logical(icellfun(vars,@(x) any(strcmp(x,moments_fields)),'return_type','mat'));
        if any(~fields_exist)
          error(sprintf('Field ''%s'' does not exist\n',vars{~fields_exist}))
        end
      end

      % now actually load metadata and requested vars
      data = NetcdfRead(filename,'getall',1,'unpackvars',1,'getmode',1,'getvaratts',0,'varstoget',{meta_data_fields{:}  vars{:} });

      % convert the structure into an emerald_dataset struct
      new_data = emerald_dataset.netcdf2emerald(data,'sweep_index',sweep_index,...
                                                'sweep_number',sweep_number,'append_to',append_to,...
                                                'meta_data_fields',meta_data_fields,'moments_fields',vars,...
                                                'vary_n_gates',vary_n_gates,'convert_coords',convert_coords);
      
      if do_check
        [result,msg] = emerald_dataset.check_dataset(new_data);
        if result
          error('Loaded data fails checks:\n%s',msg);
        end
      end
      
      data = new_data;

    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%
    %% check_dataset
    function [result,msg] = check_dataset(cstr,varargin)
    % check_dataset: Checks a struct array of emerald_dataset structs
    % usage: [result,msg] = check_dataset(cstr,'param1',value1,...)
    % cstr: struct array of emerald_dataset structs
    % optional params are anything available from check_single_dataset
    % 
    % outputs:
    %  result: error number, if found.  0 for no error.
    %  msg: string of error found.  
      for ll = 1:length(cstr)
        [result,msg] = emerald_dataset.check_single_dataset(cstr(ll),varargin{:});
        if result
          msg = sprintf('Found a problem with index %i\n%s',msg);
          return
        end
      end
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%
    %% check_single_dataset
    function [result,msg] = check_single_dataset(cstr,varargin)
    % check_single_dataset: check a emerald_dataset struct (use check_dataset for an array).
    % usage: [result,msg] = check_single_dataset(cstr,'param1',value1,...)
    % cstr: emerald_dataset struct to check
    % optional params:
    %  filename_check = 0; % if 1, this routine will ensure that the filename in the
    %    struct matches the optional parameter 'filename'
    %  filename = ''; % filename to check against if filename_check is 1.
    %  sweep_check = 0; % if 1, this routine will ensure that the sweep number in the
    %    struct matches the optional parameter 'sweep_number'
    %  sweep_number = [];
    % 
    % outputs:
    %  result: error number, if found.  0 for no error.
    %  msg: string of error found.  
    %
    % This routine check that it is a struct, that it contains the required fields.
    % 
      

      filename_check = 0;
      filename = '';

      sweep_check = 0;
      sweep_number = [];
      
      paramparse(varargin);

      result = emerald_errorcodes.OK;
      msg = '';
    
      if ~isstruct(cstr)
        result = emerald_errorcodes.STRUCT_BAD; 
        msg = 'The Emerald data structure should be a struct.';
        return
      end

      % check that the required fields exist
      [missing_fields,msg] = emerald_utils.check_fields_exist(cstr,{'file_info','meta_data','moments'});
      if ~isempty(missing_fields)
        result = emerald_errorcodes.STRUCT_MISSING_REQ; 
        msg = sprintf('The following fields are missing from the Emerald data structure:\n%s',msg);
        return
      end

      [missing_fields,msg] = emerald_utils.check_fields_exist(cstr.file_info,{'filename'});
      if ~isempty(missing_fields)
        result = emerald_errorcodes.STRUCT_MISSING_REQ;
        msg = sprintf('The following fields are missing from file_info the Emerald data structure:\n%s',msg);
        return
      end

      [missing_fields,msg] = emerald_utils.check_fields_exist(cstr.meta_data,{'range','azimuth','elevation','sweep_number','sweep_mode'});
      if ~isempty(missing_fields)
        result = emerald_errorcodes.STRUCT_MISSING_REQ;
        msg = sprintf('The following fields are missing from file_info the Emerald data structure:\n%s',msg);
        return
      end

      if filename_check
        if ~strcmp(cstr.file_info.filename,filename)
          result = emerald_errorcodes.FILENAME_MISMATCH;
          msg = 'The file names do not match.';
          return
        end
      end
      
      if sweep_check
        if ~isequal(cstr.meta_data.sweep_number,sweep_number)
          result = emerald_errorcodes.SWEEP_MISMATCH;
          msg = 'The sweep numbers do not match.';
          return
        end
      end
    
    end    
    
    
  end

  
  
  methods (Static = true, Access = private)
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% netcdf2emerald
    function new_data = netcdf2emerald(data,varargin)
    % netcdf2emerald: convert a NetcdfRead struct into an emerald_dataset struct
    % usage: new_data = netcdf2emerald(data,'param1',value1,...)
    %
    %  data: NetcdfRead struct of a cfRadial file
    % optional params:
    %  sweep_number = []; % array of sweep numbers ('sweep_number' in CFRadial file) to pull out. If
    %    empty, then the sweep_index will be used.
    %  sweep_index = 1; % array of sweep indices (index of 'sweep_number').  If equal to inf, then 
    %    all sweeps will be loaded.
    %  append_to = {}; % if this is a emerald_dataset struct, then 1 sweep can be appended (i.e. it
    %    just adds more fields to an existing emerald_dataset struct).
    %  meta_data_fields = {}; % if already known, these can be provided to speed up processing
    %  moments_fields = {}; % if already known, these can be provided to speed up processing
    %  vary_n_gates = []; % if already known, these can be provided to speed up processing
    %  convert_coords = 1; % if 1, try to convert pointing coordinates to lat/lon/alt x/y/z
    %
    % new_data = emerald_dataset struct.  Contains several substructures:
    %   file_info: information about the file
    %   inds_info: information about the upacking of the CFRadial file into multidim arrays. 
    %      probably only useful for saving back into a CFRadial file.
    %   meta_data: struct containing metadata fields
    %   moment_data: struct containing moments
    %   meta_data_info: struct containing NetcdfRead info (without data) for each metadata field
    %   moments_info: struct containing NetcdfRead info (without data) for each moments field
      
      sweep_number = [];
      sweep_index = 1;
      append_to = {};
      meta_data_fields = {};
      moments_fields = {};
      vary_n_gates = [];
      convert_coords = 1;
      
      paramparse(varargin);

      flds = fieldnames(data);
      filename = data.load_info.filename;
      
      % ensure certain data exists:
      % MIGHT WANT TO ENSURE MORE FIELDS EXIST!!!!!
      [missing_flds,msg] = emerald_utils.check_nc_fieldsdata_exist(data.vars,{'sweep_number','range','time_coverage_start','time'},'data');
      if length(missing_flds)>0
        error('There are missing required fields in the file "%s":\n%s',filename,msg);
      end      
      
      % figure out which are the avilable global netcdf fields 
      nc_flds = {'atts','unlim_dims','dims','load_info'};
      nc_flds = intersect(nc_flds,flds);

      % if needed, get the meta/moment fields
      if isempty(meta_data_fields) || isempty(vary_n_gates)
        [meta_data_fields,moment_fields,vary_n_gates] = emerald_dataset.determine_fields(data);
      end

      % if given a sweep number, then figure out which indexes the user wanted.
      if ~isempty(sweep_number)
        % figure out which sweep_index they want
        for ll = 1:length(sweep_number)
          inds = sweep_number(ll)==data.vars.sweep_number.data;
          if sum(inds)==0
            error('Problem with netcdf file ''%s''.  There appears to be no sweep_number=%g',filename,sweep_number);
          elseif sum(inds)>1
            error('Problem with netcdf file ''%s''.  There appears to be more than 1 sweep_number=%i',filename,sweep_number);
          end
          sweep_index(ll) = find(inds);
        end        
      end
      
      % if the sweep_index is inf, then just get all the sweeps.
      if any(isinf(sweep_index))
        sweep_indexes = 1:length(data.vars.sweep_number.data);
      else
        sweep_indexes = reshape(sweep_index,1,[]);
      end
      
      % check that we are not trying to append with multiple sweeps.
      if length(sweep_indexes)>1 && ~isempty(append_to)
        error('Cannot append to when getting multiple_sweeps');
      end
      
      % loop over sweeps
      for kk = 1:length(sweep_indexes)
        sweep_index = sweep_indexes(kk);

        [ray_inds,gate_inds,final_num_gates]  = emerald_dataset.determine_gate_inds(data,sweep_index,vary_n_gates);
        
        % initialize output structure
        if ~isempty(append_to)
          tmpdata = append_to;
        else
          tmpdata = struct;
          % save file_info
          tmpdata.file_info = copystruct(data,struct,'flds',nc_flds);
          tmpdata.file_info.filename = filename;
          % save inds_info
          tmpdata.inds_info.ray_inds = ray_inds;
          tmpdata.inds_info.gate_inds = gate_inds;
          
          % cp meta_data over
          for ll = 1:length(meta_data_fields)
            if isfield(data.vars.(meta_data_fields{ll}),'data')
              if length(data.vars.(meta_data_fields{ll}).dims)==0
                % if dim'less, then cp
                tmpdata.meta_data.(meta_data_fields{ll}) = data.vars.(meta_data_fields{ll}).data;
              else
                switch data.vars.(meta_data_fields{ll}).dims{1}
                  case 'time'
                    % if has dim time x whatever then limit to rays from this sweep
                    tmpdata.meta_data.(meta_data_fields{ll}) = data.vars.(meta_data_fields{ll}).data(ray_inds,:,:,:,:,:);
                  case 'sweep'
                    % if has dim 'sweep' x whatever then limit to this sweep
                    tmpdata.meta_data.(meta_data_fields{ll}) = data.vars.(meta_data_fields{ll}).data(sweep_index,:,:,:,:,:);
                  otherwise
                    % otherise just cp it over
                    tmpdata.meta_data.(meta_data_fields{ll}) = data.vars.(meta_data_fields{ll}).data;
                end
              end
              % reshape column vector char arrays
              if ischar(tmpdata.meta_data.(meta_data_fields{ll})) && ...
                  length(tmpdata.meta_data.(meta_data_fields{ll}))==prod(size(tmpdata.meta_data.(meta_data_fields{ll})))
                tmpdata.meta_data.(meta_data_fields{ll}) = reshape(tmpdata.meta_data.(meta_data_fields{ll}),1,[]);
              end
              
              % save meta_data_info
              tmpdata.meta_data_info.(meta_data_fields{ll}) = rmfield(data.vars.(meta_data_fields{ll}),'data');
            end
          end
          if isfield(tmpdata.meta_data,'range')
            % reshape range so is row vector and turn to KM, cut down the vector to final_num_gates.
            tmpdata.meta_data.range = reshape(tmpdata.meta_data.range(1:final_num_gates),1,[])/1000;
          end
        end
        
        if convert_coords
          % try to convert positions into lat/lons alts, and x/y (both elevation corrected and not), so this only has to be done once.
          try
            [tmpdata.meta_data.lat, tmpdata.meta_data.lon, tmpdata.meta_data.alt, tmpdata.meta_data.x, tmpdata.meta_data.y, tmpdata.meta_data.x_elcorr, tmpdata.meta_data.y_elcorr] = ...
                emerald_utils.polar2cart(tmpdata.meta_data.range,tmpdata.meta_data.azimuth,tmpdata.meta_data.elevation,...
                                         [tmpdata.meta_data.latitude,tmpdata.meta_data.longitude,tmpdata.meta_data.altitude/1000]);
          catch ME
            if strcmp(ME.identifier,'MATLAB:UndefinedFunction')
              warning('Cannot convert polar to cartesian because the routines are not available');
            end
          end
        end
        
        tmpdata.meta_data.time_coverage_start_mld = datenum(tmpdata.meta_data.time_coverage_start,'yyyy-mm-ddTHH:MM:SS');
        tmpdata.meta_data.time_start_mld = tmpdata.meta_data.time(1)/24/3600+tmpdata.meta_data.time_coverage_start_mld;
        
        tmpdata.moments = struct;
        % cp over the moment variables
        for ll = 1:length(moments_fields)
          % pull out the data saving into correct place
          tmp = repmat(NaN,size(gate_inds));
          tmp(~isnan(gate_inds)) = data.vars.(moments_fields{ll}).data(gate_inds(~isnan(gate_inds)));
          tmpdata.moments.(moments_fields{ll}) = tmp.';
          % save moments_info
          tmpdata.moments_info.(moments_fields{ll}) = rmfield(data.vars.(moments_fields{ll}),'data');
        end
        new_data(kk) = tmpdata;
      end
    
    
    end
    
    %%%%%%%%%%%%%%%%%
    %% determine_gate_inds
    function [ray_inds,gate_inds,final_num_gates]  = determine_gate_inds(data,sweep_index,vary_n_gates)
    % determine_gate_inds: figure out the gate_inds to transform the data from the nc file into the matlab struct
    % usage: [ray_inds,gate_inds,final_num_gates]  = determine_gate_inds(data,sweep_index,vary_n_gates)
    % inputs:
    %   data: raw nc data
    %   sweep_index: sweep index to pull out
    %   vary_n_gates: either 1 or 0 depending on whether the data has variable num of gates.
    % outputs:
    %   ray_inds: indices of rays to extract for this sweep
    %   gate_inds: indices of gates to extract for this sweep
    %   final_num_gate: the final number of gates needed.
      
      [missing_flds,msg] = emerald_utils.check_nc_fieldsdata_exist(data.vars,{'sweep_start_ray_index','sweep_end_ray_index'},'data');
      if length(missing_flds)>0
        error('There are missing required fields in the file "%s":\n%s',filename,msg);
      end      
      % FIGURE OUT HOW TO CONVERT PACKED STRUCTURE INTO NORMAL MULTIDIM ARRAY
      ray_inds = 1+(data.vars.sweep_start_ray_index.data(sweep_index):data.vars.sweep_end_ray_index.data(sweep_index));
      
      if vary_n_gates
        [missing_flds,msg] = emerald_utils.check_nc_fieldsdata_exist(data.vars,{'ray_n_gates','ray_start_index'},'data');
        if length(missing_flds)>0
          error('There are missing required fields in the file "%s":\n%s',filename,msg);
        end      
        
        % pull out the number of gates and the index starts for the rays in this sweep
        ngates = data.vars.ray_n_gates.data(ray_inds);
        rstart = data.vars.ray_start_index.data(ray_inds)+1;
        
        % figure out how many gates we need to hold the sweep
        final_num_gates = max(ngates);
        
        % the idea is to generate a matrix of indices such that 
        % data.vars.fld(gate_inds) is a num_beams x num_ranges matrix.
        % The complication is that the number of gates in an az could
        % vary.  
        
        % create the matrix (num_ranges x num_beams) if indices with rstart
        % as the first row, rstart+1 for the second, etc.
        gate_inds = ones(final_num_gates,length(ray_inds));
        gate_inds(1,:) = rstart;
        gate_inds = cumsum(gate_inds,1);
        
        % The problem is that rays that are shorter than final_num_gates will go
        % beyond their bounds.  So NaN these out.
        ng = resize((ngates+rstart-1).',size(gate_inds));
        gate_inds(gate_inds>ng) = NaN;
      else
        [missing_flds,msg] = emerald_utils.check_fields_exist(data.dims,{'time','range'});
        if length(missing_flds)>0
          error('There are missing required fields in the file "%s":\n%s',filename,msg);
        end
        gate_inds = repmat(logical(0),data.dims.time.data, data.dims.range.data);
        gate_inds(ray_inds,:) = 1;
        gate_inds = reshape(find(gate_inds),length(ray_inds),data.dims.range.data).';
        final_num_gates = data.dims.range.data;
      end
    end
    
      
    
    %%%%%%%%%%%%%%%%%%%%%%%
    %% get_cfradial_inventory_nc
    function [ncinfo,meta_data_fields,moment_fields,vary_n_gates] = get_cfradial_inventory_nc(filename,varargin)
    % get_cfradial_inventory_nc: get the cfRadial inventory from a netcdf file
    % usage: [ncinfo,meta_data_fields,moment_fields] = get_cfradial_inventory_nc(filename,'param1',value1,...)
    %  filename - string containing the nc file name
    % possible params:
    %  vars = {}; Cell array of variable names to retrieve in the read along with the standard ones
    %  
    % outputs:
    %  ncinfo: struct of the same format as the output of NetcdfRead, containing info from the nc file
    %  meta_data_fields: cell array of the field names that are meta-data
    %  moment_fields: cell array of the field names that are moment-data
      
      vars = {};
      
      paramparse(varargin);
      
      vars = cellify(vars);
      
      % just get variable and dimension ncinfo
      ncinfo = NetcdfRead(filename,'getfiledim',1,'unpackvars',1,'getvardim',2,'getmode',2,'varstoget',{'sweep_number',...
                          'sweep_start_ray_index','sweep_end_ray_index','ray_n_gates','ray_start_index','range',vars{:}});
      if nargout>1
        [meta_data_fields,moment_fields,vary_n_gates] = emerald_dataset.determine_fields(ncinfo);
      end
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%
    %% determine_fields
    function [meta_data_fields,moment_fields,vary_n_gates] = determine_fields(data)
    % determine_fields: figure out which fields are meta/moment data from a NetcdfRead struct
    % usage: [meta_data_fields,moment_fields] = determine_fields(data)
    %  where data is a NetcdfRead struct of a cfRadial file.
    % A field is deemed to be a moment if a dimension contains 'n_points'.  Otherwise it is meta-data.
      flds = fieldnames(data.vars);

      filename = data.load_info.filename;
      
      % exclude 'dims'
      if length(flds)==0
        error('There are no variables in this netcdf file');
      end

      % find the moments fields by looking for those with dimension {'n_points'}
      moment_field_inds = logical(icellfun(flds,@(x) isequal(data.vars.(x).dims,{'n_points'}),'return_type','mat'));
      uses_n_points_dim = sum(moment_field_inds)>0;

      moment_field_inds2 = logical(icellfun(flds,@(x) isequal(data.vars.(x).dims,{'time','range'}),'return_type','mat'));
      uses_timerange_dim = sum(moment_field_inds2)>0;
      
      has_n_gates_vary = isfield(data.atts,'n_gates_vary') && strcmp(lower(data.atts.n_gates_vary.data),'true');
      has_n_points_dim = isfield(data.dims,'n_points');

      vary_n_gates = 1;
      if uses_n_points_dim && ~uses_timerange_dim
        % we assume it is a varying size
        if ~has_n_gates_vary
          warning('EMERALD:MissingAttNGatesVary',sprintf('File "%s" is missing the global attribute "n_gates_vary" even though the file appears to have variable number of gates',filename));
        end     
      elseif ~uses_n_points_dim && uses_timerange_dim
        % we assume it is a fixed size
        if has_n_gates_vary
          warning('EMERALD:ExtraAttNGatesVary',sprintf('In file "%s" the global attribute "n_gates_vary" is "true" even though the file appears to have a fixed number of gates.',filename));
        end
        if has_n_points_dim
          warning('EMERALD:ExtraDimNPoints',sprintf('File "%s" contains the file dimension "n_points" even though the file appears to have a fixed number of gates',filename));
        end
        vary_n_gates = 0;
        moment_field_inds = moment_field_inds2;
      elseif uses_n_points_dim && uses_timerange_dim
        error(sprintf('This file "%s" appears to contain fields that have fixed number of gates and fields that contain variable number of gates.',filename));
      else
        warning(sprintf('This file "%s" appears to contain no moment fields.',filename));
      end
          
      moment_fields = flds(moment_field_inds);
      % find meta data by taking what is left
      [~,meta_data_inds] = setdiff(flds,moment_fields);
      meta_data_fields = flds(sort(meta_data_inds));
    end      
  
  end
  
end