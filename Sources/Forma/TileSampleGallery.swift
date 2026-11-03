import SwiftUI

struct TileSampleGallery: View {
    @Environment(\.dismiss) private var dismiss
    var select: (TileSample) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Образцы мощения").font(.title2)
                    Text("Выбери начальную форму — все её границы можно редактировать.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                    ForEach(TileSample.allCases) { sample in
                        Button { select(sample) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Canvas { context, size in
                                    let design = sample.design, bounds = design.bounds
                                    let scale = min((size.width-20)/bounds.width,(size.height-14)/bounds.height)
                                    context.translateBy(x:size.width/2,y:size.height/2)
                                    context.scaleBy(x:scale,y:scale)
                                    context.translateBy(x:-bounds.midX,y:-bounds.midY)
                                    design.paint(in:&context,i:0,j:0)
                                }.frame(height:115).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:8))
                                Text(sample.title).font(.system(size:13,weight:.medium))
                                Text(sample.subtitle).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2).frame(height:28,alignment:.topLeading)
                            }.padding(9).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text("В «Рыбе и птице» по референсу Эшера общий блок разделён на два взаимодополняющих контура. Розовые точки меняют их общую границу.")
                .font(.system(size:11)).foregroundStyle(.secondary)
        }.padding(22).frame(width:700,height:650).background(Color(nsColor:.windowBackgroundColor))
    }
}
