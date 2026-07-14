import SwiftUI

struct ResultView: View {
    let duration: TimeInterval
    @State private var rating = 0
    @State private var comment = ""
    @State private var selectedIssues: Set<String> = []
    @Environment(\.presentationMode) var presentationMode
    
    let issueCategories = [
        "Плохой перевод",
        "Задержка звука",
        "Эхо / аудио петля",
        "Обрыв соединения",
        "Не распознана речь"
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.green)
                            .padding(.top, 20)
                        
                        Text("Спасибо за беседу!")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Продолжительность: \(formatDuration(duration))")
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Оцените качество:")
                            .font(.headline)
                        
                        HStack {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title)
                                    .foregroundColor(.yellow)
                                    .onTapGesture {
                                        withAnimation {
                                            rating = star
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    if rating > 0 && rating < 4 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Что пошло не так?")
                                .font(.headline)
                            
                            FlowLayout(issues: issueCategories, selected: $selectedIssues)
                        }
                        .transition(.opacity)
                    }
                    
                    TextField("Дополнительный отзыв...", text: $comment)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.vertical, 8)
                    
                    Spacer()
                    
                    Button(action: submitFeedback) {
                        Text("Готово")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(rating > 0 ? Color.blue : Color.gray.opacity(0.4))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(rating == 0)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }
    
    private func submitFeedback() {
        presentationMode.wrappedValue.dismiss()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// Helper View for Issues Grid Selection
struct FlowLayout: View {
    let issues: [String]
    @Binding var selected: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(issues, id: \.self) { issue in
                Button(action: {
                    if selected.contains(issue) {
                        selected.remove(issue)
                    } else {
                        selected.insert(issue)
                    }
                }) {
                    Text(issue)
                        .font(.footnote)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(selected.contains(issue) ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                        .foregroundColor(selected.contains(issue) ? .blue : .primary)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selected.contains(issue) ? Color.blue : Color.clear, lineWidth: 1)
                        )
                }
            }
        }
    }
}
