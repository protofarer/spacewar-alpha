#version 100
precision highp float;

varying vec2 fragTexCoord;
varying vec4 fragColor;

uniform sampler2D texture0;
uniform vec2 resolution;
uniform float bloomThreshold;
uniform float bloomIntensity;
uniform float bloomSpread;

void main() {
    vec2 texelSize = 1.0 / resolution;
    vec3 color = texture2D(texture0, fragTexCoord).rgb;
    
    // Sample surrounding pixels for bloom
    vec3 bloom = vec3(0.0);
    float totalWeight = 0.0;
    
    // 5x5 kernel for bloom effect
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            if (x == 0 && y == 0) continue;
            
            vec2 offset = vec2(float(x), float(y)) * texelSize * bloomSpread;
            vec2 sampleCoord = fragTexCoord + offset;
            
            // Ensure we're sampling within texture bounds
            if (sampleCoord.x >= 0.0 && sampleCoord.x <= 1.0 && 
                sampleCoord.y >= 0.0 && sampleCoord.y <= 1.0) {
                
                vec3 sampleColor = texture2D(texture0, sampleCoord).rgb;
                
                // Check if this pixel is bright enough to contribute
                float brightness = max(sampleColor.r, max(sampleColor.g, sampleColor.b));
                if (brightness > bloomThreshold) {
                    // Distance-based falloff
                    float dist = length(vec2(float(x), float(y))) / 2.0;
                    float weight = 1.0 / (1.0 + dist * dist);
                    
                    bloom += sampleColor * weight * (brightness - bloomThreshold);
                    totalWeight += weight;
                }
            }
        }
    }
    
    // Normalize bloom
    if (totalWeight > 0.0) {
        bloom = bloom / totalWeight;
    }
    
    // Add bloom to original color
    vec3 result = color + bloom * bloomIntensity;
    
    // Phosphor green tint for that classic Spacewar feel
    result.g = result.g * 1.1;
    
    // Clamp to valid color range
    result = clamp(result, 0.0, 1.0);
    
    gl_FragColor = vec4(result, 1.0);
}
