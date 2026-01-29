-- ============================================================================
-- ARCHIVED: LearnTaskRules function
-- Removed in v1.6.7 - Simplified to use most recent activity log entry approach
-- Kept for historical reference
-- ============================================================================

-- Learn rules for a specific task from two observed XP values
-- Only observes: atFloor, floorXP (observed), pattern. Scale is global.
-- observationTime: timestamp of the most recent observation (to prefer newer data)
function Tracker:LearnTaskRules(taskName, last, prev, observationTime)
    if not taskName or not last or not prev then return end

    self.taskRules[taskName] = self.taskRules[taskName] or {}
    local rules = self.taskRules[taskName]

    -- Ensure prev >= last (prev is earlier = higher XP)
    if last > prev then prev, last = last, prev end

    if math.abs(last - prev) < 0.001 then
        -- AT FLOOR: consecutive same values
        -- Only update floorXP if this observation is more recent
        if not rules.floorXPTime or (observationTime and observationTime > rules.floorXPTime) then
            rules.atFloor = true
            rules.floorXP = last
            rules.floorXPTime = observationTime or time()
        end

    elseif prev > last then
        -- DECAYING: not at floor yet
        -- Detect raid boss pattern (value drops to 0)
        if last < 0.01 and prev > 0.1 then
            if not rules.floorXPTime or (observationTime and observationTime > rules.floorXPTime) then
                rules.pattern = "raidboss"
                rules.atFloor = true
                rules.floorXP = 0
                rules.floorXPTime = observationTime or time()
            end
        elseif not rules.atFloor then
            rules.atFloor = false
        end
    end

    rules.lastUpdated = time()
    rules.dataPoints = (rules.dataPoints or 0) + 1
end
