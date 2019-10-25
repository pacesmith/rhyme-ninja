#!/usr/bin/env ruby

# Rhyming utilities for Rhyme Ninja
# Used both in preprocessing and at runtime

def rhyme_signature_array(pron)
  # The rhyme signature is everything including and after the final most stressed vowel,
  # which is indicated in cmudict by a "1".
  # Some words don't have a 1, so we settle for the final secondarily-stressed vowel,
  # or failing that, the last vowel.
  #
  # input: [IH0 N S IH1 ZH AH0 N] # the pronunciation of 'incision'
  # output:        [IH  ZH AH  N] # the pronunciation of '-ision' with stress markers removed
  #
  # We remove the stress markers so that we can rhyme 'furs' [F ER1 Z] with 'yours(2)' [Y ER0 Z]
  # They will both have the rhyme signature [ER Z].
  rsig = Array.new
  pron.reverse.each { |syl|
    # we need to remove the numbers
    rsig.unshift(syl.tr("0-2", ""))
    if(syl.include?("1"))
      return rsig # we found the main stressed syllable, we can stop now
    end
  }  
  # huh? we made it all the way through without a 1. Fine, we'll settle for a secondarily-stressed syllable.
  rsig = Array.new # start over
  pron.reverse.each { |syl|
    rsig.unshift(syl.tr("0-2", ""))
    if(syl.include?("2"))
      return rsig # we found the secondarily-stressed syllable, we can stop now
    end
  }
  rsig = Array.new # start over one last time
  # I guess we'll have to settle for the last unstressed syllable
  pron.reverse.each { |syl|
    rsig.unshift(syl.tr("0-2", ""))
    if(syl.include?("0"))
      return rsig # we found the last-resort thing, we can stop now
    end
  }
  error pron
end

def rhyme_signature(pron)
  # this makes for a better hash key
  return rhyme_signature_array(pron).join(" ")
end
