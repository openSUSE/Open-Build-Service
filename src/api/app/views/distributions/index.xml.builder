xml.distributions do
  @distributions.each do |d|
    xml.distribution(vendor: d["vendor"], version: d["version"], id: d["id"]) do
      xml.name(d["name"])
      xml.project(d["project"])
      xml.reponame(d["reponame"])
      xml.repository(d["repository"])
      xml.link(d["link"])
      d["icons"].each do |i|
        attr = {url: i["url"]}
        attr[:width] = i["width"] unless i["width"].blank?
        attr[:height] = i["height"] unless i["height"].blank?
        xml.icon(attr)
      end
    end
  end
end
