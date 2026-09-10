function audit = patch_ihx_local_hot_exchange(model)
% Authorized EXPLORATORY candidate only. No source model/property writes.
model=string(model);
assert(startsWith(model,"s53_ihx_"), 'Only unique component harnesses are allowed.');
assert(contains(string(get_param(model,'FileName')),filesep+"tmp"+filesep));
root=model+"/DUT";
assert(numel(find_system(root,'BlockType','Integrator'))==10);
audit.before=inventory(root);
removed=strings(0,1); added=strings(0,1); newBlocks=strings(0,1);
for r=1:2
    prefix="IHX_region_"+r; p=root+"/"+prefix;
    expected={"h_Li","10544";"h_HeXe","1171.6";"A_region","7.031"; ...
        "m_Li_region","0.6588";"m_HeXe_region","0.00919";"m_wall_region","162.5"};
    for j=1:size(expected,1)
        assert(strcmp(get_param(p+"/"+expected{j,1},'Value'),expected{j,2}));
    end
    assert(strcmp(get_param(p+"/Gain",'Gain'),'0.5'));
    assert(strcmp(get_param(p+"/From35",'GotoTag'),'Qh05'));
    assert(strcmp(get_param(p+"/Sum4",'Inputs'),'|+-'));
    assert(strcmp(get_param(p+"/Sum10",'Inputs'),'|+-'));
    requireSource(p,'Sum4',2,'From35',1);
    requireSource(p,'Sum10',1,'Q_h',1);
    requireSource(p,'Gain',1,'Q_h',1);
    names=["LocalHotOutletDelta","LocalHotOutletProduct","LocalHotOutletHeat","LocalHotTotal"];
    for n=names
        assert(getSimulinkBlockHandle(p+"/"+n)==-1, 'Refuse repeated patch.');
    end
    add_block('simulink/Math Operations/Sum',p+"/LocalHotOutletDelta", ...
        'Inputs','+-','Position',[1260 570 1290 610]);
    add_block('simulink/Math Operations/Product',p+"/LocalHotOutletProduct", ...
        'Inputs','**','Position',[1340 570 1370 610]);
    add_block('simulink/Math Operations/Gain',p+"/LocalHotOutletHeat", ...
        'Gain','0.5','Position',[1420 570 1470 610]);
    add_block('simulink/Math Operations/Sum',p+"/LocalHotTotal", ...
        'Inputs','++','Position',[1530 570 1560 610]);
    pairs=["T_h2_out_Integrator/1","LocalHotOutletDelta/1"; ...
        "T_wall_Integrator/1","LocalHotOutletDelta/2"; ...
        "LocalHotOutletDelta/1","LocalHotOutletProduct/1"; ...
        "A*h_h/1","LocalHotOutletProduct/2"; ...
        "LocalHotOutletProduct/1","LocalHotOutletHeat/1"; ...
        "Gain/1","LocalHotTotal/1"; ...
        "LocalHotOutletHeat/1","LocalHotTotal/2"; ...
        "LocalHotOutletHeat/1","Sum4/2"; ...
        "LocalHotTotal/1","Sum10/1"];
    delete_line(p,'From35/1','Sum4/2');
    delete_line(p,'Q_h/1','Sum10/1');
    for j=1:size(pairs,1)
        add_line(p,pairs(j,1),pairs(j,2),'autorouting','on');
        added(end+1,1)=prefix+"/"+pairs(j,1)+" -> "+prefix+"/"+pairs(j,2);
    end
    removed=[removed;prefix+"/From35/1 -> "+prefix+"/Sum4/2"; ...
        prefix+"/Q_h/1 -> "+prefix+"/Sum10/1"]; %#ok<AGROW>
    newBlocks=[newBlocks;prefix+"/"+names(:)]; %#ok<AGROW>
end
audit.after=inventory(root);
oldPaths=string({audit.before.blocks.path}); newPaths=string({audit.after.blocks.path});
assert(isequal(sort(setdiff(newPaths,oldPaths)),sort(newBlocks.')));
for k=1:numel(oldPaths)
    j=find(newPaths==oldPaths(k));
    assert(isscalar(j)&&isequal(audit.before.blocks(k),audit.after.blocks(j)), ...
        'An existing block parameter changed unexpectedly.');
end
audit.removedEdges=setdiff(audit.before.edges,audit.after.edges);
audit.addedEdges=setdiff(audit.after.edges,audit.before.edges);
assert(isequal(sort(audit.removedEdges),sort(removed)));
assert(isequal(sort(audit.addedEdges),sort(added)));
assert(numel(find_system(root,'BlockType','Integrator'))==10);
audit.newBlocks=newBlocks;
audit.scope='Candidate only: local hot-cell exchange; no coefficient, property, cold-equation or state-count changes.';
end

function requireSource(root,dest,port,source,sourcePort)
ph=get_param(root+"/"+dest,'PortHandles'); line=get_param(ph.Inport(port),'Line');
assert(line~=-1); sp=get_param(line,'SrcPortHandle');
assert(string(get_param(get_param(sp,'Parent'),'Name'))==source);
assert(get_param(sp,'PortNumber')==sourcePort);
end

function s=inventory(root)
paths=sort(string(find_system(root,'LookUnderMasks','all','Type','Block')));
paths=paths(paths~=root);
s.blocks=struct('path',{},'type',{},'parameters',{}); s.edges=strings(0,1);
for k=1:numel(paths)
    b=paths(k); dp=get_param(b,'DialogParameters'); params=struct;
    if isempty(dp), keys={}; else, keys=sort(fieldnames(dp)); end
    for j=1:numel(keys), params.(keys{j})=get_param(b,keys{j}); end
    s.blocks(k)=struct('path',extractAfter(b,root+"/"), ...
        'type',string(get_param(b,'BlockType')),'parameters',jsonencode(params));
    ph=get_param(b,'PortHandles');
    for j=1:numel(ph.Inport)
        line=get_param(ph.Inport(j),'Line');
        if line==-1, continue; end
        sp=get_param(line,'SrcPortHandle');
        if sp==-1, continue; end
        src=string(get_param(sp,'Parent'));
        s.edges(end+1,1)=extractAfter(src,root+"/")+"/"+get_param(sp,'PortNumber')+ ...
            " -> "+extractAfter(b,root+"/")+"/"+j;
    end
end
s.edges=sort(s.edges);
end
