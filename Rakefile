task :gen, [:input, :output] do |t, args|
  input = args[:input]
  output = args[:output]
  puts "input: #{input}, output: #{output}"
  if input.nil? || output.nil? 
    puts "Usage: rake gen[input.adoc, output.html]"
    exit
  end
  sh "asciidoctor -b w-html -r ./convert.rb #{input} -o #{output}"
end
