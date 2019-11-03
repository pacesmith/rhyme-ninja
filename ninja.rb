#!/usr/bin/env ruby
# coding: utf-8

#
# control parameters
# Don't tweak these here, tweak them in rhyme.rb
#

DEFAULT_DATAMUSE_MAX = 550
$datamuse_max = DEFAULT_DATAMUSE_MAX
$debug_mode = false;
$output_format = 'text';
$display_word_frequencies = false;

#
# Public interface: rhyme_ninja(word1, word2, goal, output_format='text', debug_mode=false, datamuse_max=400)
# see rhyme.rb for documentation
# 

require 'net/http'
require 'uri'
require 'json'
require 'cgi'
require_relative 'dict/utils_rhyme'

#
# utilities
#

def debug(string)
  if($debug_mode)
    puts string
  end
end

def cgi_print(string)
  if($output_format == 'cgi')
    print string
  end
end

#
# Local rhyme computation
#

$word_dict = nil
def word_dict()
  # word => [frequency, pronunciations]
  # pronunciations = [pronunciation1, pronunciation2 ...]
  # pronunciation = [syllable1, syllable1, ...]
  if $word_dict.nil?
    $word_dict = load_word_dict_as_hash
  end
  $word_dict
end

$rdict = nil # rhyme signature -> words hash
def rdict
  # rhyme_signature => [rhyming_word1 rhyming_word2 ...]
  # where rhyme_signature = "syllable1 syllable2 ..."
  if $rdict.nil?
    $rdict = load_rhyme_signature_dict_as_hash
  end
  $rdict
end

def load_word_dict_as_hash()
  JSON.parse(File.read("dict/word_dict.json")) or die "First run dict/dict.rb to generate dictionary caches"
end

def load_rhyme_signature_dict_as_hash()
  JSON.parse(File.read("dict/rhyme_signature_dict.json")) or die "First run dict/dict.rb to generate dictionary caches"
end

def pronunciations(word, lang)
  case lang
  when "en"
    return english_pronunciations(word)
  when "es"
    return spanish_pronunciations(word)
  else
    abort "Unexpected language #{lang}"
  end
end

def english_pronunciations(word)
  word_info = word_dict[word]
  if(word_info)
    return word_info[1]
  else
    return [ ]
  end
end

def spanish_pronunciations(word)
  english_pronunciations(word) # stub
end

def frequency(word)
  word_info = word_dict[word]
  if(word_info)
    return word_info[0]
  else
    return 0
  end
end  

def rdict_lookup(rsig)
  rdict[rsig] || [ ]
end

def find_rhyming_words(word, lang="en")
  # merges multiple pronunciations of WORD
  # use our local dictionaries, we don't need the Datamuse API for simple rhyme lookup
  rhyming_words = Array.new
  for pron in pronunciations(word, lang)
    for rhyme in find_rhyming_words_for_pronunciation(pron)
      rhyming_words.push(rhyme)
    end
  end
  rhyming_words.delete(word)
  if(rhyming_words)
    rhyming_words = rhyming_words.uniq
  end
  return rhyming_words || [ ]
end

def find_rhyming_words_for_pronunciation(pron)
  # use our local dictionaries, we don't need the Datamuse API for simple rhyme lookup
  results = Array.new
  rsig = rhyme_signature(pron)
  rdict_lookup(rsig).each { |rhyme|
    results.push(rhyme)
  }
  return results || [ ]
end

# def is_stupid_rhyme(pron, rhyme)
  # word.include?(rhyme) or rhyme.include?(word)
  # consider filtering out words where the rhyming syllabme is identical. But for now it's better to overinclude than overexclude.
#   word == rhyme
# end

#
# Datamuse stuff
#

def results_to_words(results)
  words = [ ]
  results.each { |result|
    words.push(result["word"])
  }
  return words
end
  
def find_related_words(word, include_self=false, lang)
  words = results_to_words(find_datamuse_results("", word, lang))
  if(include_self)
    words.push(word)
  end
  return words
end

def find_related_rhymes(rhyme, rel, lang)
  results_to_words(find_datamuse_results(rhyme, rel, lang))
end

def find_datamuse_results(rhyme, rel, lang)
  request = "https://api.datamuse.com/words?"
  if(lang != "en")
    request += "v=#{lang}&"
  end
  if(rhyme != "")
    request += "rel_rhy=#{rhyme}&";
  end
  if(rel != "")
    request += "ml=#{rel}&";
  end
  if($datamuse_max != 100) # 100 is the default
    request += "max=#{$datamuse_max}" # no trailing &, must be the last thing
  end
  request = URI.escape(request)

  debug "#{request}<br/><br/>";
  uri = URI.parse(request);
  response = Net::HTTP.get_response(uri)
  if(response.body() != "")
    JSON.parse(response.body());
  else
    # @todo refactor
    puts "Error connecting to Datamuse API: #{request} <br> Try again later."
    abort
  end
end

def find_rhyming_tuples(input_rel1, lang)
  # Rhyming word sets that are related to INPUT_REL1.
  # Each element of the returned array is an array of words that rhyme with each other and are all related to INPUT_REL1.
  related_rhymes = Hash.new {|h,k| h[k] = [] } # hash of arrays
  relateds1 = find_related_words(input_rel1, true, lang)
  relateds1.each { |rel1|
    for rel1pron in pronunciations(rel1, lang)
      rsig = rhyme_signature(rel1pron)
      debug "Rhymes for #{rel1} [#{rsig}]:"
      find_rhyming_words_for_pronunciation(rel1pron).each { |rhyme1|
        if(relateds1.include? rhyme1) # we only care about relateds of input_rel1
          related_rhymes[rsig].push(rhyme1)
          debug " #{rhyme1}"
        end
      }
    end
  }
  tuples = [ ]
  related_rhymes.each { |rsig, relrhymes|
    relrhymes.sort!.uniq!
    if(relrhymes.length > 1)
      tuples.push(relrhymes.sort!)
    end
  }
  return tuples
end

def find_rhyming_pairs(input_rel1, input_rel2, lang)
  # Pairs of rhyming words where the first word is related to INPUT_REL1 and the second word is related to INPUT_REL2
  # Each element of the returned array is a pair of rhyming words [W1 W2] where W1 is related to INPUT_REL1 and W2 is related to INPUT_REL2
  related_rhymes = Hash.new {|h,k| h[k] = [] } # hash of arrays
  relateds1 = find_related_words(input_rel1, true, lang)
  relateds2 = find_related_words(input_rel2, true, lang)
  relateds1.each { |rel1|
    # rel1 is a word related to input_rel1. We're looking for rhyming pairs [rel1 rel2].
    debug "rhymes for #{rel1}:<br>"
    # If we find a word 'RHYME' that rhymes with rel1 and is related to input_rel2, we win!
    find_rhyming_words(rel1).each { |rhyme| # check all rhymes of rel1, call each one 'RHYME'
      if(relateds2.include? rhyme) # is RHYME related to input_rel2? If so, we win!
        related_rhymes[rel1].push(rhyme)
        debug rhyme;
      end
    }
    debug "<br><br>"
  }
  pairs = [ ]
  related_rhymes.each { |relrhyme1, relrhyme2_list|
    if(!relrhyme2_list.empty?)
      relrhyme2_list.each { |relrhyme2|
        pairs.push([relrhyme1, relrhyme2])
      }
    end
  }
  return pairs
end

#
# Display
#

def print_tuple(tuple, lang)
  # print TUPLE separated by slashes
  i = 0
  cgi_print "<div class='tuple'>"
  tuple.each { |elem|
    if(i > 0)
      print " / "
    end
    print_word(elem, lang)
    i += 1
  }
  cgi_print "</div>"
  puts
  STDOUT.flush
end

def print_tuples(tuples, lang)
  # return boolean, did I print anything? i.e. was TUPLES nonempty?
  success = !tuples.empty?
  if(success)
    tuples.sort.uniq.each { |tuple|
      print_tuple(tuple, lang)
    }
  end
  return success
end

def print_words(words, lang)
  success = !words.empty?
  if(success)
    words.sort.uniq.each { |word|
      cgi_print "<div class='output_tuple'>"
      cgi_print "<span class='output_word'>"
      print_word(word, lang)
      if($display_word_frequencies)
        print " (#{frequency(word)})"
      end
      cgi_print "</span>"
      cgi_print "</div>"
      puts
    }
  end
  return success
end

def ubiquity(word)
  # 0-255
  result = 0
  case frequency(word)
  when 0
    result = 0
  when 1
    result = 40
  when 2..5
    result = 80
  when 6..20
    result = 120
  when 21..100
    result = 160
  when 101..1000
    result = 200
  else
    result = 255
  end
  result
end

def rare?(word)
  frequency(word) == 0
end

def filter_out_rare_words(words)
  good = words.reject{ |w| rare?(w) }
  bad = words.select { |w| rare?(w) }
  return good, bad
end

def print_word(word, lang)
  got_rhymes = !pronunciations(word, lang).empty?
  if(got_rhymes)
    # @todo urlencode
    cgi_print lang(lang, "<a href='rhyme.rb?word1=#{word}'>", "<a href='rimar.rb?word1=#{word}'>")
  end
  ubiq = ubiquity(word)
#  cgi_print "<span style='color: rgb(#{ubiq}, #{ubiq}, #{ubiq});'>"
  print word
#  cgi_print "</span>"
  if(got_rhymes)
    cgi_print "</a>"
  end
end

#
# Central dispatcher
#

def rhyme_ninja(word1, word2, goal, lang='en', output_format='text', debug_mode=false, datamuse_max=DEFAULT_DATAMUSE_MAX)
  $output_format = output_format
  $debug_mode = debug_mode
  $datamuse_max = datamuse_max
  
  result = nil
  dregs = [ ]
  result_type = :error # :words, :tuples, :bad_input, :vacuous, :error
  result_header = "Unexpected error."

  # special cases
  if(word1 == "" and word2 == "")
    return nil, :vacuous, ""
  end
  if(word1 == "" and word2 != "")
    word1, word2 = word2, word1
  end
  if(word1 == "smiley" and word2 == "love" and goal == "related_rhymes")
    result_header = "<font size=80><bold>KYELI!</bold></font>"; # easter egg for Kyeli
    return [ ], :words, result_header
  end

  # main list of cases
  case goal
  when "rhymes"
    result_header = lang(lang, "Rhymes for", "Rimas para") + " \"<span class='focal_word'>#{word1}</span>\":<div class='results'>"
    result, dregs = filter_out_rare_words(find_rhyming_words(word1, lang))
    result_type = :words
  when "related"
    result_header = lang(lang, "Words related to", "Palabras relacionadas con") + " \"<span class='focal_word'>#{word1}</span>\":<div class='results'>"
    result, dregs = filter_out_rare_words(find_related_words(word1, false, lang))
    result_type = :words
  when "set_related"
    result_header = lang(lang, "Rhyming word sets related to", "Conjuntos de rimas relacionadas con") + " \"<span class='focal_word'>#{word1}</span>\":<div class='results'>"
    result = find_rhyming_tuples(word1, lang)
    result_type = :tuples
  when "pair_related"
    if(word1 == "" or word2 == "")
      result_header = lang(lang, "I need two words to find rhyming pairs. For example, Word 1 = <span class='focal_word'>crime</span>, Word 2 = <span class='focal_word'>heaven</span>", "Necesito dos palabras para buscar pares rimandos")
      result_type = :bad_input
    else
      result_header = lang(lang, "Rhyming word pairs where the first word is related to", "Pares de palabras rimandas, la primera palabra está relacionada con") + " \"<span class='focal_word'>#{word1}</span>\" " + lang(lang, "and the second word is related to ", "y la segunda palabra está relacionada con") + " \"<span class='focal_word'>#{word2}</span>\":<div class='results'>"
      result = find_rhyming_pairs(word1, word2, lang)
      result_type = :tuples
    end
  when "related_rhymes"
    if(word1 == "" or word2 == "")
      result_header = lang(lang, "I need two words to find related rhyming pairs. For example, Word 1 = <span class='focal_word'>please</span>, Word 2 = <span class='focal_word'>cats</span>", "Necesito dos palabras para buscar pares rimandos relacionados.")
      result_type = :bad_input
    else
      result_header = lang(lang, "Rhymes for", "Rimas para") + " \"<span class='focal_word'>#{word1}</span>\" " + lang(lang, "that are related to", "que están relacionadas con") + " \"<span class='focal_word'>#{word2}</span>\":<div class='results'>"
      result = find_related_rhymes(word1, word2, lang)
      result_type = :words
    end
  else
    result_header = lang(lang, "Invalid selection.", "selección invalida")
    result_type = :bad_input
  end
  debug "result = #{result}"
  debug "result_type = #{result_type}"
  return result, dregs, result_type, result_header
end

#
# Utilities
#

def rhymes?(word1, word2)
  # Does word1 rhyme with word2?
  find_rhyming_words(word1).include?(word2)
end

def related?(word1, word2, include_self=false)
  # Is word1 conceptually related to word2?
  find_related_words(word1, include_self).include?(word2)
end
