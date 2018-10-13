local RandomBinaryCriterion, parent = torch.class('w2nn.RandomBinaryCriterion','nn.Criterion')

local function create_filters(ch, n, k)
   local filter = w2nn.RandomBinaryConvolution(ch, n, k, k)
   -- channel identify
   for i = 1, ch do
      filter.weight[i]:fill(0)
      filter.weight[i][i][math.floor(k/2)+1][math.floor(k/2)+1] = 1
   end
   return filter
end
function RandomBinaryCriterion:__init(ch, n, k)
   parent.__init(self)
   self.gamma = 0.1
   self.n = n or 32
   self.k = k or 3
   self.ch = ch
   self.filter1 = create_filters(self.ch, self.n, self.k)
   self.filter2 = self.filter1:clone()
   self.diff = torch.Tensor()
   self.diff_abs = torch.Tensor()
   self.square_loss_buff = torch.Tensor()
   self.linear_loss_buff = torch.Tensor()
   self.input = torch.Tensor()
   self.target = torch.Tensor()
end
function RandomBinaryCriterion:updateOutput(input, target)
   if input:dim() == 2 then
      local k = math.sqrt(input:size(2) / self.ch)
      input = input:reshape(input:size(1), self.ch, k, k)
   end
   if target:dim() == 2 then
      local k = math.sqrt(target:size(2) / self.ch)
      target = target:reshape(target:size(1), self.ch, k, k)
   end
   self.input:resizeAs(input):copy(input):clamp(0, 1)
   self.target:resizeAs(target):copy(target):clamp(0, 1)

   local lb1 = self.filter1:forward(self.input)
   local lb2 = self.filter2:forward(self.target)

   -- huber loss
   self.diff:resizeAs(lb1):copy(lb1)
   for i = 1, lb1:size(1) do
      self.diff[i]:add(-1, lb2[i])
   end
   self.diff_abs:resizeAs(self.diff):copy(self.diff):abs()
   
   local square_targets = self.diff[torch.lt(self.diff_abs, self.gamma)]
   local linear_targets = self.diff[torch.ge(self.diff_abs, self.gamma)]
   local square_loss = self.square_loss_buff:resizeAs(square_targets):copy(square_targets):pow(2.0):mul(0.5):sum()
   local linear_loss = self.linear_loss_buff:resizeAs(linear_targets):copy(linear_targets):abs():add(-0.5 * self.gamma):mul(self.gamma):sum()

   --self.outlier_rate = linear_targets:nElement() / input:nElement()
   self.output = (square_loss + linear_loss) / lb1:nElement()

   return self.output
end

function RandomBinaryCriterion:updateGradInput(input, target)
   local d2 = false
   if input:dim() == 2 then
      d2 = true
      local k = math.sqrt(input:size(2) / self.ch)
      input = input:reshape(input:size(1), self.ch, k, k)
   end
   local norm = self.n / self.input:nElement()
   self.gradInput:resizeAs(self.diff):copy(self.diff):mul(norm)
   local outlier = torch.ge(self.diff_abs, self.gamma)
   self.gradInput[outlier] = torch.sign(self.diff[outlier]) * self.gamma * norm
   local grad_input = self.filter1:updateGradInput(input, self.gradInput)
   if d2 then
      grad_input = grad_input:reshape(grad_input:size(1), grad_input:size(2) * grad_input:size(3) * grad_input:size(4))
   end
   return grad_input
end
