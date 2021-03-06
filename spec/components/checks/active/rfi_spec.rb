require 'spec_helper'

describe name_from_filename do
    include_examples 'check'

    def self.elements
        [ Element::Form, Element::Link, Element::Cookie, Element::Header ]
    end

    def issue_count_per_element
        {
            Element::Form   => 12,
            Element::Link   => 12,
            Element::Cookie => 12,
            Element::Header => 6
        }
    end

    easy_test
end
