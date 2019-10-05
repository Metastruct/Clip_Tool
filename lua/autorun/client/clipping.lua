local Tag='cliptool'

local Clips = {}
local RenderOverride
local MaxClips={}
local RenderInsideInfo={}
local RenderOverrideEnabled={}

-- purely debug info. Do not use.
if not Clipping then
	Clipping = {}
	Clipping.Clips = Clips
	Clipping.RenderOverride = RenderOverride
	Clipping.MaxClips = MaxClips
	Clipping.RenderInsideInfo = RenderInsideInfo
	Clipping.RenderOverrideEnabled = RenderOverrideEnabled
end

local function Check(ent)
	local eid = ent:EntIndex()
	local c = Clips[eid]
	if c == nil then return end
	if next(c) then
		if not RenderOverrideEnabled[eid] then
			if ent.RenderOverride then
				ent.ClipRenderOverride = RenderOverride
				Msg"[Clip] " print("Colliding RenderOverride. Add compatibility manually for ",ent)
				return
			end
			RenderOverrideEnabled[eid] = true
			ent.RenderOverride = RenderOverride
		else
			if not ent.RenderOverride then
				Msg"[Clip DBG] " print("Lost RenderOverride. Ent: ",ent)
				ent.RenderOverride = RenderOverride
			end
		end
	else
		if RenderOverrideEnabled[eid] then
			RenderOverrideEnabled[eid] = false
			ent.RenderOverride = nil
		end
		ent.ClipRenderOverride = nil
		Clips[eid] = nil
	end
end

local function MarkDirty(eid)
	local ent = Entity(eid)
	if not ent:IsValid() then return end
	Check(ent)
end

hook.Add("NotifyShouldTransmit",Tag,function(ent,s)
	if not s then return end
	Check(ent)
end)
hook.Add("NetworkEntityCreated",Tag,function(ent)
	Check(ent)
end)



local cvar = CreateClientConVar("max_clips_per_prop", 7, true, false)

cvars.AddChangeCallback("max_clips_per_prop", function(_, _, new)
	new = tonumber(new)

	for ent, _ in pairs(Clips) do
		MaxClips[ent] = math.min(new, #Clips[ent])
	end
end)

local function ReadAngleAsFloat()
	return Angle(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
end

local function ReadClip()
	return {ReadAngleAsFloat(), net.ReadDouble(), false }
end

local function AddPropClip(ent, clip)
	Clips[ent] = Clips[ent] or {}
	Clips[ent][#Clips[ent] + 1] = clip
	MaxClips[ent] = math.min(cvar:GetInt(), #Clips[ent])

end

local clipping_new_clip = 1
local clipping_render_inside = 2
local clipping_all_prop_clips = 3
local clipping_remove_all_clips = 4
local clipping_remove_clip = 5

local t={
	"clipping_new_clip",
	"clipping_render_inside",
	"clipping_all_prop_clips",
	"clipping_remove_all_clips",
	"clipping_remove_clip"
}
net.Receive(Tag, function()
	local mode = net.ReadUInt(5)
	local ent = net.ReadUInt(16)
	Msg"[Clip Net] "print("mode=",t[mode] or mode,"entid=",ent,"ent=",Entity(ent),Clips[ent] and "<already something>" or "")

	if mode == clipping_new_clip then
		AddPropClip(ent, ReadClip())
	elseif mode == clipping_render_inside then
		local enabled = tobool(net.ReadBit())
		RenderInsideInfo[ent] = enabled
	elseif mode == clipping_all_prop_clips then
		local clips = net.ReadInt(16)
		for i = 1, clips do
			AddPropClip(ent, ReadClip())
		end
	elseif mode == clipping_remove_all_clips then
		if Clips[ent] then
			table.Empty(Clips[ent])
		end
	elseif mode == clipping_remove_clip then
		local index = net.ReadInt(16)
		if not Clips[ent] then return end
		table.remove(Clips[ent], index)
		MaxClips[ent] = math.min(cvar:GetInt(), #Clips[ent])
	end
	MarkDirty(ent)
end)


local render_EnableClipping = render.EnableClipping
local render_PushCustomClipPlane = render.PushCustomClipPlane
local render_PopCustomClipPlane = render.PopCustomClipPlane
local render_CullMode = render.CullMode
local entm = FindMetaTable("Entity")
local ent_LocalToWorldAngles = entm.LocalToWorldAngles
local ent_LocalToWorld = entm.LocalToWorld
local ent_SetupBones = entm.SetupBones
local ent_EntIndex = entm.EntIndex
local ent_DrawModel = entm.DrawModel
local vecm = FindMetaTable("Vector")
local vec_Dot = vecm.Dot
local angm = FindMetaTable("Angle")
local ang_Forward = angm.Forward
local IsValid = IsValid
local n, enabled, curclips, obbcenter

RenderOverride = function(self)
	local eid = ent_EntIndex(self)
	
	local entclips = Clips[eid]
	if not entclips or not next(entclips) then
		return
	end
	
	enabled = render_EnableClipping(true)
	for i = 1, MaxClips[eid] do
		curclips = entclips[i]
		if not curclips then continue end
		n = ang_Forward(ent_LocalToWorldAngles(self, curclips[1]))
		obbcenter = curclips[3]
		if not obbcenter then
			obbcenter = self:OBBCenter()
			curclips[3] = obbcenter
		end
		render_PushCustomClipPlane(n, vec_Dot(ent_LocalToWorld(self, obbcenter) + n * curclips[2], n))
	end

	ent_DrawModel(self)

	if RenderInsideInfo[eid] then
		render_CullMode(MATERIAL_CULLMODE_CW)
		ent_DrawModel(self)
		render_CullMode(MATERIAL_CULLMODE_CCW)
	end

	for i = 1, MaxClips[eid] do
		render_PopCustomClipPlane()
	end

	render_EnableClipping(enabled)
end


hook.Add("InitPostEntity", Tag, function()
	timer.Simple(5, function()
		net.Start(Tag)
		net.SendToServer()
	end)
end)