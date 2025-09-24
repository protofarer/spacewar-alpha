#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;

out vec4 finalColor;

void main()
{
	vec4 texelColor = texture(texture0, fragTexCoord) * fragColor;
	 float brightness = (texelColor.r + texelColor.g + texelColor.b) / 3.0;
     if (brightness < 0.04) {
		 finalColor = vec4(0.0,0.0,0.0,1.0);
	 } else {
		 finalColor = texelColor;
	 }
}
