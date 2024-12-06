task :test_whtml do
  sh "asciidoctor -b w-html -r ./convert.rb test.adoc"
  sh "tidy -config tidy.cfg test.html"
  sh "asciidoctor -b w-html -r ./convert.rb test2.adoc"
  sh "tidy -config tidy.cfg test2.html"
  sh "asciidoctor -b w-html -r ./convert.rb test3.adoc"
  sh "tidy -config tidy.cfg test3.html"
end
