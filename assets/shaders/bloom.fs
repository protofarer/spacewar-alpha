#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec2 resolution;
uniform float bloomThreshold;
uniform float bloomIntensity;
uniform float bloomSpread;

out vec4 finalColor;

void main() {
    vec2 texelSize = 1.0 / resolution;
    vec3 color = texture(texture0, fragTexCoord).rgb;
    
    // Sample surrounding pixels for bloom
    vec3 bloom = vec3(0.0);
    float totalWeight = 0.0;
    
    // 9x9 kernel centered on current pixel
    for (int x = -4; x <= 4; x++) {
        for (int y = -4; y <= 4; y++) {
            if (x == 0 && y == 0) continue; // Skip center pixel
            
            vec2 offset = vec2(float(x), float(y)) * texelSize * bloomSpread;
            vec3 sample = texture(texture0, fragTexCoord + offset).rgb;
            
            // Check if this pixel is bright enough to contribute
            float brightness = max(sample.r, max(sample.g, sample.b));
            if (brightness > bloomThreshold) {
                // Distance-based falloff
                float dist = length(vec2(float(x), float(y))) / 4.0;
                float weight = 1.0 / (1.0 + dist * dist);
                
                bloom += sample * weight * (brightness - bloomThreshold);
                totalWeight += weight;
            }
        }
    }
    
    // Normalize bloom
    if (totalWeight > 0.0) {
        bloom /= totalWeight;
    }
    
    // Add bloom to original color
    vec3 result = color + bloom * bloomIntensity;
    
    // Phosphor green tint
    result.g *= 1.1;
    
    finalColor = vec4(result, 1.0);
}
