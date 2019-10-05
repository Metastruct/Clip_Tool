local Tag = 'cliptool'
AddCSLuaFile("autorun/client/clipping.lua")
AddCSLuaFile("autorun/client/preview.lua")
util.AddNetworkString(Tag)

if not Clipping then
	Clipping = {}
	Clipping.RenderingInside = {}
	Clipping.EntityClips = {}
	Clipping.Queue = {}
end

local Clipping = Clipping
local net_clipping_new_clip = 1
local net_clipping_render_inside = 2
local net_clipping_all_prop_clips = 3
local net_clipping_remove_all_clips = 4
local net_clipping_remove_clip = 5

local function StartMsg(id, ent)
	net.Start(Tag)
	net.WriteUInt(id, 5)
	net.WriteUInt(ent:EntIndex(), 16)
end

local function WriteAngleAsFloat(angle)
	net.WriteFloat(angle.p)
	net.WriteFloat(angle.y)
	net.WriteFloat(angle.r)
end

local function WriteClip(clip)
	WriteAngleAsFloat(clip[1])
	net.WriteDouble(clip[2])
end

local function SendEntClip(ent, clip)
	StartMsg(net_clipping_new_clip, ent)
	WriteClip(clip)
	net.Broadcast()
end

function Clipping.RenderInside(ent, enabled)
	Clipping.RenderingInside[ent] = enabled
	StartMsg(net_clipping_render_inside, ent)
	net.WriteBit(tobool(enabled))
	net.Broadcast()
	duplicator.StoreEntityModifier(ent, "clipping_render_inside", {enabled})
end

function Clipping.GetRenderInside(ent)
	return tobool(Clipping.RenderingInside[ent])
end

function Clipping.NewClip(ent, clip)
	if not Clipping.EntityClips[ent] then
		Clipping.EntityClips[ent] = {clip}
	else
		table.insert(Clipping.EntityClips[ent], clip)
	end

	local t = ent:GetTable() and ent:GetTable().EntityMods

	-- Get rid of old junk. TODO: legacy conversion?
	if t and t.clips then
		t.clips = nil
	end

	ent:CallOnRemove("RemoveFromClippedTable", function(ent)
		Clipping.RemoveClips(ent, true)
	end)

	-- Without table.Copy will crash due to references.
	duplicator.StoreEntityModifier(ent, "clipping_all_prop_clips", table.Copy(Clipping.EntityClips[ent]))
	SendEntClip(ent, clip)
end

function Clipping.SendAllPropClips(ent, player)
	StartMsg(net_clipping_all_prop_clips, ent)
	net.WriteInt(#Clipping.EntityClips[ent], 16)

	for k, clip in pairs(Clipping.EntityClips[ent]) do
		WriteClip(clip)
	end

	net.Send(player)
end

function Clipping.RemoveClips(ent, keepdata)
	Clipping.EntityClips[ent] = nil

	if not keepdata and ent["EntityMods"] then
		ent["EntityMods"]["clipping_all_prop_clips"] = nil
	end

	StartMsg(net_clipping_remove_all_clips, ent)
	net.Broadcast()
end

function Clipping.RemoveClip(ent, index)
	if (IsValid(ent) and Clipping.EntityClips[ent] ~= nil) then
		table.remove(Clipping.EntityClips[ent], index)
		StartMsg(net_clipping_remove_clip, ent)
		net.WriteInt(index, 16)
		net.Broadcast()
	end
end

function Clipping.GetClips(ent)
	return Clipping.EntityClips[ent]
end

net.Receive(Tag, function(_, ply)
	for ent, _ in pairs(Clipping.EntityClips) do
		if IsValid(ent) and IsValid(ply) then
			table.insert(Clipping.Queue, {ent, ply})
		end
	end
end)

hook.Add("Tick", "Clipping_Send_All_Clips", function()
	if not next(Clipping.Queue) then return end
	local q = Clipping.Queue[#Clipping.Queue]
	Clipping.SendAllPropClips(q[1], q[2])
	Clipping.Queue[#Clipping.Queue] = nil
end)

duplicator.RegisterEntityModifier("clipping_all_prop_clips", function(p, ent, data)
	if not IsValid(ent) or not data then return end

	for _, clip in pairs(data) do
		Clipping.NewClip(ent, clip)
	end
end)

duplicator.RegisterEntityModifier("clipping_render_inside", function(p, ent, data)
	if not IsValid(ent) then return end
	Clipping.RenderInside(ent, data[1])
end)