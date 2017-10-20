xml.productlist( count: @products.count ) do
  @products.map { |p| xml.product(name: p.name, cpe: p.cpe, 
                                  originproject: p.package.project.name,
                                  originpackage: p.package.name,
                                  mtime: p.package.updated_at.to_i)
  }
end

