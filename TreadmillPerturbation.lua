-- seconds before perturbation to start/restart recording
recordingStartOffset = recordingStartOffset or 3
recordingStopWaitTime = recordingStopWaitTime or 1

-- ramp up and ramp down duration on start and stop treadmill movement
SETTINGS_STOP_START_SECONDS = SETTINGS_STOP_START_SECONDS or 3

-- ramp up and ramp down duration on start and stop treadmill movement
SETTINGS_COUNTDOWN_SOUND_SECONDS = SETTINGS_COUNTDOWN_SOUND_SECONDS or 4

updateFromInputsRequested = updateFromInputsRequested or false
stopRequested = stopRequested or false

-- treadmill state variable: 'none', 'countdown', 'starting', 'stopping', 'steady', 'rising', 'settle', 'falling'
trdmlState = trdmlState or 'none'

-- variable to store change in state time of treadmill
trdmlStateTime = trdmlStateTime or frametime()

-- variable to store start speed
trdmlStartSpeed = trdmlStartSpeed or 0

-- variable to store target speed
trdmlTargetSpeed = trdmlTargetSpeed or 0

-- variable to store current set speed
trdmlCurrentSpeed = trdmlCurrentSpeed or 0


-- variable to store current set speed
trdmlAcc = trdmlAcc or 0

-- variable to set which side should speed set for: 0 => none, 1 => left, 2 => right, 3 => both
trdmlTargetSides = trdmlTargetSides or 0

perturbationIndex = perturbationIndex or 0

perturbationWaitForEvent = perturbationWaitForEvent or 'none'
perturbationTargetSides = perturbationTargetSides or 0
nextPerturbTime = nextPerturbTime or 0
nextRecordingTime = nextRecordingTime or 0
perturbations_size = perturbations_size or 0
perturbations_all = perturbations_all or {}
perturbation_current = perturbation_current or {}

isRecordingStarted = isRecordingStarted or false

myScriptStarted = myScriptStarted or false

myScriptShouldStop = myScriptShouldStop or false


function closeLogFile()
    if logFile ~= nil then
        logFile:flush()
        logFile:close()
        logFile = nil
    end
end

function createLogFile()
    local logDir = '%APPLICATIONS%\\TNamayeshi\\Recordings\\%SUBJECTID%\\'
    logDir = convertresourcefilenamefromalias(logDir)
    os.execute('mkdir "' .. logDir .. '"')
    print('Log dir "' .. logDir .. '"')
    local logFileName = 'Script.log'
    local index = 1
    while file_exists(logDir .. logFileName) do
        index = index + 1
        logFileName = 'Script-' .. string.format("%03d", index) .. ' .log'
    end
    logFile = io.open(logDir .. logFileName, "a")
    if logFile ~= nil then
        info('Log file ' .. logFileName .. ' created!')
        return true
    end
    print('could not create the log file')
    return false
end

function log(msg)
    print(msg)
    if logFile == nil then
        if not createLogFile() then
            return
        end
    end
    local date_table = os.date("*t")
    local ms = string.match(tostring(os.clock()), "%d%.(%d+)")
    local hour, minute, second = date_table.hour, date_table.min, date_table.sec
    local year, month, day = date_table.year, date_table.month, date_table.day
    local time = string.format("%04d-%02d-%02d %02d:%02d:%02d.%s", year, month, day, hour, minute, second, ms)
    logFile:write(time .. ' > ' .. msg .. '\n')
    logFile:flush()
end

function setTrdmlState(state)
    if trdmlState ~= state then
        trdmlStateTime = frametime()
        log('go from state "' .. trdmlState .. '" to "' .. state .. '"') -- for debug
        trdmlState = state
        return true
    end
    return false
end

function file_exists(name)
    local f = io.open(name, "r")
    return f ~= nil and io.close(f)
end

function computeNextPerturbationTime()
    if PARAM_TreadmillPerturbEnable then
        nextPerturbTime = frametime() + PARAM_TreadmillPerturbIntervalMin
        if PARAM_TreadmillPerturbRandomInterval then
            local randomDiff = (PARAM_TreadmillPerturbIntervalMax - PARAM_TreadmillPerturbIntervalMin) * math.random()
            nextPerturbTime = nextPerturbTime + randomDiff
        end
        nextRecordingTime = nextPerturbTime - recordingStartOffset - recordingStopWaitTime
    else
        nextPerturbTime = 0
        nextRecordingTime = 0
    end

    local diff = nextPerturbTime - frametime()
    log('Next perturbation in ' .. diff .. ' seconds!') -- for debug
end

function random_compare(a, b)
    return a.random < b.random
end

function randomizePerturbationsListOrder()
    log('Perturbations list permutation randomized!') -- for debug
    for i = 1, perturbations_size do
        perturbations_all[i].random = math.random()
    end
    table.sort(perturbations_all, random_compare)
end

function hasBitSet(value, bitIndex)
    if bitIndex == 1 then return value % 2 == 1 end
    if bitIndex == 2 then return value == 2 or value == 3 end
    return false
end

function createPerturbationsList()
    local p_count = 0

    for side = 1, 2 do
        for type = 1, 2 do
            if PARAM_TreadmillPerturbOnset == 4 then
                if hasBitSet(PARAM_TreadmillPerturbLeg, side) and
                    hasBitSet(PARAM_TreadmillPerturbType, type) then
                    p_count = p_count + 1
                    local p = { side = side, type = type, onset = 0, random = 0 }
                    perturbations_all[p_count] = p
                end
            else
                for onset = 1, 2 do
                    if hasBitSet(PARAM_TreadmillPerturbLeg, side) and
                        hasBitSet(PARAM_TreadmillPerturbType, type) and
                        hasBitSet(PARAM_TreadmillPerturbOnset, onset) then
                        p_count = p_count + 1
                        local p = { side = side, type = type, onset = onset, random = 0 }
                        perturbations_all[p_count] = p
                    end
                end
            end
        end
    end

    perturbations_size = p_count
    log('Perturbations list updated with ' .. p_count .. ' entries') -- for debug

    if PARAM_TreadmillPerturbRandom then
        randomizePerturbationsListOrder()
    end
end

function updateFromInputs()
    log('Update parameters from inputs') -- for debug
    updateFromInputsRequested = false

    PARAM_TreadmillPerturbEnable = inputs.get('TreadmillPerturbEnable') > 0

    PARAM_TreadmillPerturbLeg = inputs.get('TreadmillPerturbLeg')
    PARAM_TreadmillPerturbType = inputs.get('TreadmillPerturbType')
    PARAM_TreadmillPerturbOnset = inputs.get('TreadmillPerturbOnset')

    PARAM_TreadmillPerturbRandom = inputs.get('TreadmillPerturbRandom') > 0

    PARAM_TreadmillSpeed = inputs.get('TreadmillSpeed')

    PARAM_TreadmillPerturbRandomInterval = inputs.get('TreadmillPerturbRandomInterval') > 0
    PARAM_TreadmillPerturbIntervalMin = inputs.get('TreadmillPerturbIntervalMin')
    PARAM_TreadmillPerturbIntervalMax = inputs.get('TreadmillPerturbIntervalMax')

    PARAM_TreadmillPerturbAccMag = inputs.get('TreadmillPerturbAccMag')
    PARAM_TreadmillPerturbRiseTime = inputs.get('TreadmillPerturbRiseTime')
    PARAM_TreadmillPerturbSettleTime = inputs.get('TreadmillPerturbSettleTime')
    PARAM_TreadmillPerturbFallTime = inputs.get('TreadmillPerturbFallTime')

    if recordingStartOffset > PARAM_TreadmillPerturbIntervalMin then
        recordingStartOffset = PARAM_TreadmillPerturbIntervalMin / 2
    end

    -- Initialize the pseudo random number generator
    math.randomseed(os.time())
    math.random();
    math.random();
    math.random()
    -- done. :-)

    perturbationWaitForEvent = 'none'

    createPerturbationsList()

    if trdmlState == 'steady' then
        computeNextPerturbationTime()
    end
end

function setRecording(enable)
    if isRecordingStarted == enable then
        return
    end
    isRecordingStarted = enable
    if enable then
         log('Mocap start record ...')
         broadcast('StartRecord')
         outputs.set("Phidgets.RecordRelay", 1)
    else
         log('Mocap stop record !')
         broadcast('StopRecord')
         outputs.set("Phidgets.RecordRelay", 0)
    end
end

function setPerturbationVars(startSpeed, targetSpeed, duration, targetSides)
    log('setPerturbationVars> startSpeed:' .. startSpeed .. ', targetSpeed:' .. targetSpeed .. ', duration:' .. duration .. ', targetSides:' .. targetSides) -- for debug
    perturbationTargetSides = targetSides

    trdmlTargetSides = targetSides
    trdmlCurrentSpeed = startSpeed
    trdmlStartSpeed = startSpeed
    trdmlTargetSpeed = targetSpeed

    trdmlAcc = (targetSpeed - startSpeed) / duration
end

function updateSpeed()
    local elapsedTime = frametime() - trdmlStateTime
    if perturbationTargetSides > 0 then
        local finishSpeedChange = false
        trdmlCurrentSpeed = trdmlStartSpeed + (elapsedTime * trdmlAcc)
        if trdmlAcc > 0 then
            if trdmlCurrentSpeed >= trdmlTargetSpeed then
                trdmlCurrentSpeed = trdmlTargetSpeed
                finishSpeedChange = true
            end
        else
            if trdmlCurrentSpeed <= trdmlTargetSpeed then
                trdmlCurrentSpeed = trdmlTargetSpeed
                finishSpeedChange = true
            end
        end

        if perturbationTargetSides == 1 or perturbationTargetSides == 3 then
            outputs.set('LeftBelt.Speed', trdmlCurrentSpeed)
        end

        if perturbationTargetSides == 2 or perturbationTargetSides == 3 then
            outputs.set('RightBelt.Speed', trdmlCurrentSpeed)
        end

        if finishSpeedChange then
            perturbationTargetSides = 0
            if trdmlState == 'rising' then
                setTrdmlState('settle')
            elseif trdmlState == 'falling' then
                setTrdmlState('steady')
            elseif trdmlState == 'starting' then
                setTrdmlState('steady')
            elseif trdmlState == 'stopping' then
                setTrdmlState('none')
                myScriptShouldStop = true
            end

            if trdmlState == 'steady' then
                computeNextPerturbationTime()
            end
        end
    elseif trdmlState == 'settle' then
        if elapsedTime >= PARAM_TreadmillPerturbSettleTime then
            setTrdmlState('falling')
            setPerturbationVars(trdmlTargetSpeed, trdmlStartSpeed, PARAM_TreadmillPerturbFallTime, trdmlTargetSides)
        end
    elseif trdmlState == 'countdown' then
        if elapsedTime >= SETTINGS_COUNTDOWN_SOUND_SECONDS then
            setTrdmlState('starting')
            setPerturbationVars(0, PARAM_TreadmillSpeed, SETTINGS_STOP_START_SECONDS, 3)
        end
    end
end

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function startPerturbation()
    if perturbationIndex > 0 and (perturbationIndex % perturbations_size == 0) then
        randomizePerturbationsListOrder()
    end

    perturbationIndex = perturbationIndex + 1
    local p_inx = perturbationIndex
    if p_inx > perturbations_size then
        p_inx = ((p_inx - 1) % perturbations_size) + 1
    end

    perturbation_current = perturbations_all[p_inx];
    if perturbation_current == nil then
        log('Can not find perturbation at index ' .. p_inx) -- for debug
        return
    end

    local onset = perturbation_current.onset
    local pside = perturbation_current.side
    local ptype = perturbation_current.type

    log('Perturbation> Onset:' .. onset .. ', Side: ' .. pside .. ', Type: ' .. ptype)

    if onset == 0 then

        local acc = PARAM_TreadmillPerturbAccMag
        if ptype == 2 then
            acc = -acc
        end
        local targetSpeed = PARAM_TreadmillSpeed + (acc * PARAM_TreadmillPerturbRiseTime)
        setPerturbationVars(PARAM_TreadmillSpeed, targetSpeed, PARAM_TreadmillPerturbRiseTime, pside)
        broadcast('PerturbationStart')
        setTrdmlState('rising')
    else


        local left = false
        local hillStrike = false
        left = hasBitSet(pside, 1)
        hillStrike = hasBitSet(onset, 1)

        log('Waiting for perturbation triger event ... ') -- for debug

        if left then
            if hillStrike then
                perturbationWaitForEvent = "1"
            else
                perturbationWaitForEvent = "2"
            end
        else
            if hillStrike then
                perturbationWaitForEvent = "3"
            else
                perturbationWaitForEvent = "4"
            end
        end
    end
end

if not myScriptStarted then
    myScriptStarted = true
    log('Lua script execution started at time: ' .. frametime())
end

updateSpeed()

for i = 1, actions() do
    if action(i) == 'Action' then
        if trdmlState == 'none' then
            updateFromInputs()
            setTrdmlState('countdown')
            broadcast('PlayCountdown')
        else
            updateFromInputsRequested = true
        end
    elseif action(i) == 'Custom 6' then
        if trdmlState == 'steady' then
            setTrdmlState('stopping')
            setPerturbationVars(PARAM_TreadmillSpeed, 0, SETTINGS_STOP_START_SECONDS, 3)
        elseif trdmlState ~= 'none' then
            stopRequested = true
        end
    elseif string.find(action(i), 'Custom') then
        -- start perturbation if waiting for custom action
        if perturbationWaitForEvent ~= 'none' then
            local eventNumber = string.sub(action(i), 8)
            if eventNumber == perturbationWaitForEvent then
                log('Event ID "' .. eventNumber .. '" triggered!') -- for debug
                perturbationWaitForEvent = 'none'
                local pside = perturbation_current.side
                local ptype = perturbation_current.type
                local acc = PARAM_TreadmillPerturbAccMag
                if ptype == 2 then
                    acc = -acc
                end
                local targetSpeed = PARAM_TreadmillSpeed + (acc * PARAM_TreadmillPerturbRiseTime)
                setPerturbationVars(PARAM_TreadmillSpeed, targetSpeed, PARAM_TreadmillPerturbRiseTime, pside)
                broadcast('PerturbationStart')
                setTrdmlState('rising')
            else
                log('Event ID "' .. eventNumber .. '" received instead of "' .. perturbationWaitForEvent .. '"') -- for debug
            end
        end
    end
end

if trdmlState == 'steady' and stopRequested then
    stopRequested = false
    setTrdmlState('stopping')
    setPerturbationVars(PARAM_TreadmillSpeed, 0, SETTINGS_STOP_START_SECONDS, 3)
end

if trdmlState == 'steady' and updateFromInputsRequested then
    updateFromInputs()
end

if perturbationWaitForEvent == 'none' and trdmlState == 'steady' then
    if nextRecordingTime > 0.1 and frametime() >= nextRecordingTime then
        if isRecordingStarted then
            setRecording(false)
            nextRecordingTime = nextRecordingTime + recordingStopWaitTime
        else
            nextRecordingTime = 0
            setRecording(true)
        end        
    end

    if nextPerturbTime > 0.1 and frametime() >= nextPerturbTime then
        nextPerturbTime = 0
        startPerturbation()
    end
end


if myScriptShouldStop then
    setRecording(false)
    myScriptStarted = false
    myScriptShouldStop = false
    broadcast('StopAll')
    log('Lua script execution stopped at time: ' .. frametime())
    closeLogFile()
end
