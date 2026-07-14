import SwiftUI

struct ResultView: View {
    let duration: TimeInterval
    @State private var rating: Int = 0
    @State private var comment: String = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Сессия завершена")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Продолжительность: \(Int(duration)) сек")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            Text("Оцените качество перевода:")
                .font(.headline)
            
            HStack {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= rating ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .font(.title)
                        .onTapGesture {
                            rating = index
                        }
                }
            }
            .padding()
            
            TextField("Комментарий (необязательно)", text: $comment)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Отправить отзыв") {
                // Submit feedback logic
                presentationMode.wrappedValue.dismiss()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .padding()
    }
}
