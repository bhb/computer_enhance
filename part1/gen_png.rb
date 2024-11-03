require 'chunky_png'

# Replace 'file_path.data' with your file's path
file_path = 'dump.data'

# Assuming the image width and height are known
width, height = 64, 64  # Replace with actual dimensions

# Create a new image
image = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::TRANSPARENT)

# Read the file
data = File.binread(file_path).unpack('C*')

# Iterate over the data and set the pixels
(0...height).each do |y|
  (0...width).each do |x|
    i = 4 * (y * width + x)
    image[x, y] = ChunkyPNG::Color.rgba(data[i], data[i + 1], data[i + 2], data[i + 3])
  end
end

# Display the image (or save it)
image.save('output.png')
