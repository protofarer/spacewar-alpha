package game

import rl "vendor:raylib"


Shaders :: [Shader_Kind]rl.Shader

Shader_Kind :: enum {
	FX_Bloom,
}

Bloom_Shader :: struct {
	shader: rl.Shader,
	resolution_loc: i32,
	threshold_loc: i32,
	intensity_loc: i32,
	spread_loc: i32,
	resolution: Vec2,
	threshold: f32,
	intensity: f32,
	spread: f32,
}

setup_bloom_shader :: proc() -> Bloom_Shader {
	// TODO: get enums for windows, mac, wasm
	shader: rl.Shader
	when ODIN_OS == .Linux || ODIN_OS == .Darwin || ODIN_OS == .Windows{
		shader = rl.LoadShader(nil, "assets/shaders/bloom.fs")
	} else when ODIN_ARCH == .wasm32 {
		pr("INFO: Loading WebGL shaders...")
		shader = rl.LoadShader("assets/shaders/bloom_web.vs", "assets/shaders/bloom_web.fs")
		// shader = rl.LoadShader(nil, "assets/shaders/bloom_web.fs")
	}

	if shader.id == 0 {
		pr("ERROR: Failed to load bloom shader")
	}

	bloom_shader_data: Bloom_Shader
	bloom_shader_data.shader = shader

    // Get uniform locations
    bloom_shader_data.resolution_loc = rl.GetShaderLocation(bloom_shader_data.shader, "resolution")
    bloom_shader_data.threshold_loc = rl.GetShaderLocation(bloom_shader_data.shader, "bloomThreshold")
    bloom_shader_data.intensity_loc = rl.GetShaderLocation(bloom_shader_data.shader, "bloomIntensity")
    bloom_shader_data.spread_loc = rl.GetShaderLocation(bloom_shader_data.shader, "bloomSpread")

	bloom_shader_data.resolution = {LOGICAL_SCREEN_WIDTH, LOGICAL_SCREEN_HEIGHT}
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.resolution_loc, &bloom_shader_data.resolution, rl.ShaderUniformDataType.VEC2)

    bloom_shader_data.intensity = 1.25
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.intensity_loc, &bloom_shader_data.intensity, rl.ShaderUniformDataType.FLOAT)

	bloom_shader_data.threshold = 0.9
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.threshold_loc, &bloom_shader_data.threshold, rl.ShaderUniformDataType.FLOAT)

    bloom_shader_data.spread = 1.1
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.spread_loc, &bloom_shader_data.spread, rl.ShaderUniformDataType.FLOAT)

	return bloom_shader_data
}
