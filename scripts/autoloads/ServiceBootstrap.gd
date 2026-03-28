extends Node

## ServiceBootstrap — instantiates all services, wires them into typed managers,
## and registers them via ServiceRegistry.
##
## All add_child calls are deferred so that service _ready() methods run after
## the scene tree is stable. The registry object is fully configured before
## it enters the tree.
##
## Views that need a manager before the registry enters the tree can access it
## via `(get_node("/root/ServiceBootstrap")).registry.ui_scale` etc.

var registry: ServiceRegistry

func _ready() -> void:
	# --- Instantiate services ---
	var fog_svc := FogService.new()
	fog_svc.name = "FogService"

	var map_svc := MapService.new()
	map_svc.name = "MapService"

	var net_svc := NetworkService.new()
	net_svc.name = "NetworkService"

	var gs_svc := GameStateService.new()
	gs_svc.name = "GameStateService"

	var ps_svc := ProfileService.new()
	ps_svc.name = "ProfileService"

	var persistence_svc := PersistenceService.new()
	persistence_svc.name = "PersistenceService"

	var input_svc := InputService.new()
	input_svc.name = "InputService"

	var token_svc := TokenService.new()
	token_svc.name = "TokenService"

	var history_svc := HistoryService.new()
	history_svc.name = "HistoryService"

	var measurement_svc := MeasurementService.new()
	measurement_svc.name = "MeasurementService"

	var effect_svc := EffectService.new()
	effect_svc.name = "EffectService"

	var ui_scale_svc := UIScaleService.new()
	ui_scale_svc.name = "UIScaleService"

	# --- Build registry and wire managers ---
	registry = ServiceRegistry.new()
	registry.name = "ServiceRegistry"

	var fog_mgr := FogManager.new()
	fog_mgr.service = fog_svc
	fog_mgr.model = FogModel.new()
	registry.fog = fog_mgr

	var map_mgr := MapManager.new()
	map_mgr.service = map_svc
	registry.map = map_mgr

	var net_mgr := NetworkManager.new()
	net_mgr.service = net_svc
	registry.network = net_mgr

	var gs_model := GameStateModel.new()
	var gs_mgr := GameStateManager.new()
	gs_mgr.service = gs_svc
	gs_mgr.model = gs_model
	gs_svc._model = gs_model
	registry.game_state = gs_mgr

	var ps_model := ProfileModel.new()
	var ps_mgr := ProfileManager.new()
	ps_mgr.service = ps_svc
	ps_mgr.model = ps_model
	ps_svc._model = ps_model
	registry.profile = ps_mgr

	var persistence_mgr := PersistenceManager.new()
	persistence_mgr.service = persistence_svc
	registry.persistence = persistence_mgr

	var input_model := InputModel.new()
	var input_mgr := InputManager.new()
	input_mgr.service = input_svc
	input_mgr.model = input_model
	registry.input = input_mgr

	var token_mgr := TokenManager.new()
	token_mgr.service = token_svc
	registry.token = token_mgr

	var history_mgr := HistoryManager.new()
	history_mgr.service = history_svc
	registry.history = history_mgr

	var measurement_mgr := MeasurementManager.new()
	measurement_mgr.service = measurement_svc
	registry.measurement = measurement_mgr

	var effect_mgr := EffectManager.new()
	effect_mgr.service = effect_svc
	registry.effect = effect_mgr

	var ui_scale_mgr := UIScaleManager.new()
	ui_scale_mgr.service = ui_scale_svc
	registry.ui_scale = ui_scale_mgr

	# --- Add to scene tree (deferred to avoid ready-order races) ---
	# Views that need a scale factor early get it via UIScaleManager's DPI
	# fallback (no tree lookup required).  ToolPalette stores its manager ref
	# directly so it never calls get_node during _ready().
	var root := get_tree().root
	root.call_deferred("add_child", registry)
	root.call_deferred("add_child", fog_svc)
	root.call_deferred("add_child", map_svc)
	root.call_deferred("add_child", net_svc)
	root.call_deferred("add_child", gs_svc)
	root.call_deferred("add_child", ps_svc)
	root.call_deferred("add_child", persistence_svc)
	root.call_deferred("add_child", input_svc)
	root.call_deferred("add_child", token_svc)
	root.call_deferred("add_child", history_svc)
	root.call_deferred("add_child", measurement_svc)
	root.call_deferred("add_child", effect_svc)
	root.call_deferred("add_child", ui_scale_svc)

	print("ServiceBootstrap: all services registered")
