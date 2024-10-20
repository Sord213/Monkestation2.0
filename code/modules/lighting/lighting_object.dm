/datum/lighting_object
	///the underlay we are currently applying to our turf to apply light
	var/mutable_appearance/current_underlay
	var/mutable_appearance/additive_underlay

	///whether we are already in the SSlighting.objects_queue list
	var/needs_update = FALSE

	///the turf that our light is applied to
	var/turf/affected_turf

GLOBAL_LIST_EMPTY(default_lighting_underlays_by_z)

/datum/lighting_object/New(turf/source)
	if(!isturf(source))
		qdel(src, force=TRUE)
		stack_trace("a lighting object was assigned to [source], a non turf! ")
		return

	. = ..()

	current_underlay = new(GLOB.default_lighting_underlays_by_z[source.z])

	additive_underlay = mutable_appearance(LIGHTING_ICON, ("light"), source.z, source, LIGHTING_PLANE_ADDITIVE, 255, RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM)

	additive_underlay.blend_mode = BLEND_ADD

	affected_turf = source
	if (affected_turf.lighting_object)
		qdel(affected_turf.lighting_object, force = TRUE)
		stack_trace("a lighting object was assigned to a turf that already had a lighting object!")

	affected_turf.lighting_object = src
	// Default to fullbright, so things can "see" if they use view() before we update
	affected_turf.luminosity = 1

	// This path is really hot. this is faster
	// Really this should be a global var or something, but lets not think about that yes?
	for(var/turf/open/space/space_tile in RANGE_TURFS(1, affected_turf))
		space_tile.enable_starlight()

	for(var/turf/open/floor/plating/ocean/space_tile in RANGE_TURFS(1, affected_turf))
		if(space_tile.has_starlight)
			space_tile.enable_starlight()

	needs_update = TRUE
	SSlighting.objects_queue += src

/datum/lighting_object/Destroy(force)
	if (!force)
		return QDEL_HINT_LETMELIVE
	SSlighting.objects_queue -= src
	if (isturf(affected_turf))
		affected_turf.lighting_object = null
		affected_turf.luminosity = 1
		affected_turf.underlays -= current_underlay
		affected_turf.underlays -= additive_underlay
	affected_turf = null
	return ..()

/datum/lighting_object/proc/update()
	// To the future coder who sees this and thinks
	// "Why didn't he just use a loop?"
	// Well my man, it's because the loop performed like shit.
	// And there's no way to improve it because
	// without a loop you can make the list all at once which is the fastest you're gonna get.
	// Oh it's also shorter line wise.
	// Including with these comments.

	var/static/datum/lighting_corner/dummy/dummy_lighting_corner = new


#ifdef VISUALIZE_LIGHT_UPDATES
	affected_turf.add_atom_colour(COLOR_BLUE_LIGHT, ADMIN_COLOUR_PRIORITY)
	animate(affected_turf, 10, color = null)
	addtimer(CALLBACK(affected_turf, TYPE_PROC_REF(/atom, remove_atom_colour), ADMIN_COLOUR_PRIORITY, COLOR_BLUE_LIGHT), 10, TIMER_UNIQUE|TIMER_OVERRIDE)
#endif

	var/datum/lighting_corner/red_corner = affected_turf.lighting_corner_SW || dummy_lighting_corner
	var/datum/lighting_corner/green_corner = affected_turf.lighting_corner_SE || dummy_lighting_corner
	var/datum/lighting_corner/blue_corner = affected_turf.lighting_corner_NW || dummy_lighting_corner
	var/datum/lighting_corner/alpha_corner = affected_turf.lighting_corner_NE || dummy_lighting_corner

	var/max = max(red_corner.largest_color_luminosity, green_corner.largest_color_luminosity, blue_corner.largest_color_luminosity, alpha_corner.largest_color_luminosity)

	var/rr = red_corner.cache_r
	var/rg = red_corner.cache_g
	var/rb = red_corner.cache_b

	var/gr = green_corner.cache_r
	var/gg = green_corner.cache_g
	var/gb = green_corner.cache_b

	var/br = blue_corner.cache_r
	var/bg = blue_corner.cache_g
	var/bb = blue_corner.cache_b

	var/ar = alpha_corner.cache_r
	var/ag = alpha_corner.cache_g
	var/ab = alpha_corner.cache_b

	#if LIGHTING_SOFT_THRESHOLD != 0
	var/set_luminosity = max > LIGHTING_SOFT_THRESHOLD
	#else
	// Because of floating points™?, it won't even be a flat 0.
	// This number is mostly arbitrary.
	var/set_luminosity = max > 1e-6
	#endif

	if((rr & gr & br & ar) && (rg + gg + bg + ag + rb + gb + bb + ab == 8))
		//anything that passes the first case is very likely to pass the second, and addition is a little faster in this case
		affected_turf.underlays -= current_underlay
		current_underlay.icon_state = "lighting_transparent"
		current_underlay.color = null
		affected_turf.underlays += current_underlay
	else if(!set_luminosity)
		affected_turf.underlays -= current_underlay
		current_underlay.icon_state = "lighting_dark"
		current_underlay.color = null
		affected_turf.underlays += current_underlay
	else
		affected_turf.underlays -= current_underlay
		current_underlay.icon_state ="light"
		current_underlay.color = list(
			rr, rg, rb, 00,
			gr, gg, gb, 00,
			br, bg, bb, 00,
			ar, ag, ab, 00,
			00, 00, 00, 01
		)

		affected_turf.underlays += current_underlay

	if(red_corner.applying_additive || green_corner.applying_additive || blue_corner.applying_additive || alpha_corner.applying_additive)
		affected_turf.underlays -= additive_underlay
		additive_underlay.icon_state = "light"
		var/arr = red_corner.add_r
		var/arb = red_corner.add_b
		var/arg = red_corner.add_g

		var/agr = green_corner.add_r
		var/agb = green_corner.add_b
		var/agg = green_corner.add_g

		var/abr = blue_corner.add_r
		var/abb = blue_corner.add_b
		var/abg = blue_corner.add_g

		var/aarr = alpha_corner.add_r
		var/aarb = alpha_corner.add_b
		var/aarg = alpha_corner.add_g

		additive_underlay.color = list(
			arr, arg, arb, 00,
			agr, agg, agb, 00,
			abr, abg, abb, 00,
			aarr, aarg, aarb, 00,
			00, 00, 00, 01
		)
		affected_turf.underlays += additive_underlay
	else
		affected_turf.underlays -= additive_underlay

	affected_turf.luminosity = set_luminosity
